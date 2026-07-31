package jsonrpc

import std.collection.concurrent.*
import std.sync.*
import stdx.log.*
import stdx.serialization.serialization.*
import stdxx.*

public class Connection <: Resource {
    private let locker = Mutex()
    private let nextId = AtomicInt32(0)
    private let pending = ConcurrentHashMap<RequestId, LinkedBlockingQueue<ResultOrError>>()
    private let inflight = ConcurrentHashMap<RequestId, CancellationToken>()

    public Connection(private let transport: JsonRpcTransport, private let handler: Handler, private let logger: Logger) {}

    /**
     * @throws RpcException - if params are not serialized to array|object|null
     * @throws TransportException - if the frame cannot be written
     */
    public func notify<P>(method: String, params: P): Unit where P <: Serializable<P> {
        send(NotificationBody(method, params: serializeParams(params)).enveloped())
    }

    /**
     * @throws RpcException - if params are not serialized to array|object|null
     * @throws TransportException - if the frame cannot be written
     */
    public func request<P, R>(method: String, params: P): PendingRequest<R> where P <: Serializable<P>,
        R <: Serializable<R> {
        let id = Integer(nextId.fetchAdd(1))
        let slot = LinkedBlockingQueue<ResultOrError>(1)
        pending.add(id, slot)
        try {
            send(RequestBody(id, method, params: serializeParams(params)).enveloped())
        } catch (e: Exception) {
            // nothing will ever answer an id that never reached the wire
            forget(id)
            throw e
        }

        PendingRequest<R>(id, slot, {=> forget(id)})
    }

    public func cancel(id: RequestId): Unit {
        if (let Some(tok) <- inflight.get(id)) {
            tok.cancel()
        }
    }

    public func isClosed(): Bool {
        transport.isClosed()
    }

    public func close(): Unit {
        transport.close()
        for ((_, token) in inflight) {
            token.cancel()
        }
        abandonPending()
    }

    /**
     * Reads until the peer hangs up or the connection is closed. Undecodable frames
     * are answered and skipped; only a broken frame boundary ends the loop early.
     *
     * However it ends, no caller is left waiting on an answer that can no longer
     * arrive.
     *
     * @throws TransportException - if the framing is lost in either direction
     */
    public func serve(): Unit {
        try {
            while (true) {
                let body = try {
                    transport.read() ?? break
                } catch (e: RpcException) {
                    // the frame did not decode but the stream is still in sync, so the
                    // peer gets an error against a null id and the loop reads on
                    send(ResponseBody.error(Null, e.responseError).enveloped())
                    continue
                } catch (e: Exception) {
                    // a `close` racing a blocked read pulls the stream out from under
                    // it; that is the shutdown itself, not a fault to report
                    if (isClosed()) {
                        break
                    }
                    throw e
                }

                match (body) {
                    case Request(req) => spawn {serveRequest(req)}
                    case Notification(note) => spawn {serveNotification(note)}
                    case Response(resp) => complete(resp)
                }
            }
        } finally {
            abandonPending()
        }
    }

    // @note every `spawn`ed body catches internally: an exception escaping a thread
    // is dumped to stderr by the runtime even when nobody reads its future.
    private func serveRequest(req: RequestBody): Unit {
        try {
            let cancelToken = CancellationToken()
            if (inflight.addIfAbsent(req.id, cancelToken).isSome()) {
                // the id is taken, so a response carrying it would be ambiguous
                send(
                    ResponseBody
                        .error(Value(req.id),
                            ResponseError(ErrorCode.INVALID_REQUEST, "request id ${req.id} is already in flight"))
                        .enveloped())
                return
            }

            let resultOrError = try {
                handler.onRequest(req.method, req.params, cancelToken)
            } catch (e: RpcException) {
                ResultOrError.Error(e.responseError)
            } catch (e: Exception) {
                ResultOrError.Error(ResponseError(ErrorCode.INTERNAL_ERROR, e.message))
            } finally {
                inflight.remove(req.id)
            }

            send(ResponseBody(Value(req.id), resultOrError).enveloped())
        } catch (e: Exception) {
            if (isClosed()) {
                // the connection went away mid-request; there is nobody left to answer
                logger.debug("dropped the answer to \"${req.method}\" - the connection is closed")
                return
            }
            logger.error("serve request \"${req.method}\" failed", [("cause", e)])
        }
    }

    private func serveNotification(note: NotificationBody): Unit {
        try {
            handler.onNotification(note.method, note.params)
        } catch (e: Exception) {
            logger.error("serve notification \"${note.method}\" failed", [("cause", e)])
        }
    }

    private func complete(resp: ResponseBody): Unit {
        let id = match (resp.id) {
            case Value(id) => id
            case Null =>
                // a null id means the peer could not tell which of our frames it was
                // rejecting, so there is nothing to correlate it against
                logger.error("peer rejected an unidentifiable message", [("cause", describe(resp.resultOrError))])
                return
        }

        match (pending.remove(id)) {
            case Some(slot) => slot.add(resp.resultOrError)
            case None => logger.warn("dropped a response for an unknown request id ${id}")
        }
    }

    /**
     * Stops correlating an outbound id, so whatever answers it later is dropped.
     */
    private func forget(id: RequestId): Unit {
        pending.remove(id)
    }

    private func abandonPending(): Unit {
        for ((id, _) in pending) {
            if (let Some(slot) <- pending.remove(id)) {
                slot.add(
                    ResultOrError.Error(
                        ResponseError(ErrorCode.INTERNAL_ERROR, "the connection ended before the peer answered")))
            }
        }
    }

    /**
     * @throws TransportException - if the frame cannot be written
     */
    private func send(body: Body): Unit {
        synchronized(locker) {
            transport.write(body)
        }
    }

    /**
     * @throws RpcException - if params are not serialized to array|object|null
     */
    private func serializeParams<P>(params: P): ?ArrayOrObject where P <: Serializable<P> {
        let dm = params.serialize()
        if (dm is DataModelNull) {
            return None
        }

        try {
            ArrayOrObject.deserialize(dm)
        } catch (_: DataModelException) {
            throw RpcException(ErrorCode.INVALID_PARAMS, "invalid params type", data: dm)
        }
    }

    private func describe(resultOrError: ResultOrError): String {
        match (resultOrError) {
            case Error(err) => "${err.code}: ${err.message}"
            case Result(_) => "no error given"
        }
    }
}
