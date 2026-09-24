package jsonrpc

import std.sync.AtomicBool

/**
 * A peer request handed to a `Handler`, together with the one right to answer it.
 * The answer need not come from the thread that received it: a handler may answer
 * in place, or carry the request off to a thread of its own and answer from there.
 *
 * Exactly one answer reaches the peer. Once one has been given, later ones are
 * dropped - so the connection's own fallback, an error for a handler that threw,
 * can never overwrite an answer that already went out.
 */
public class InboundRequest {
    private let answered = AtomicBool(false)

    /**
     * Public so a `Handler` can be driven without a connection behind it, the way
     * its tests do.
     *
     * @param deliver - writes the answer and unregisters the id; it must not throw,
     * since the thread answering may have nobody above it to catch
     */
    public InboundRequest(
        public let id: RequestId,
        public let method: String,
        public let params: ?ArrayOrObject,
        public let cancellation: CancellationToken,
        private let deliver: (ResultOrError) -> Unit
    ) {}

    public prop isAnswered: Bool {
        get() {
            answered.load()
        }
    }

    /**
     * Sends the answer, unless one has already been sent. Never throws: a
     * connection that closed in the meantime has nobody left to tell.
     *
     * @return whether this call was the one that answered
     */
    public func respond(resultOrError: ResultOrError): Bool {
        if (answered.swap(true)) {
            return false
        }
        deliver(resultOrError)
        true
    }

    /**
     * Runs `answer` and responds with what it gives. A throw becomes an error
     * response - an `RpcException` its own error, anything else an
     * `INTERNAL_ERROR` - so it is a safe body for a `spawn`: nothing escapes it.
     */
    public func respondWith(answer: () -> ResultOrError): Bool {
        let resultOrError = try {
            answer()
        } catch (e: Exception) {
            ResultOrError.Error(responseErrorOf(e))
        }
        respond(resultOrError)
    }
}

/**
 * The error a handler's throw stands for on the wire: an `RpcException` its own
 * error, anything else an `INTERNAL_ERROR`.
 */
public func responseErrorOf(e: Exception): ResponseError {
    match (e) {
        case rpc: RpcException => rpc.responseError
        case _ => ResponseError(ErrorCode.INTERNAL_ERROR, e.message)
    }
}
