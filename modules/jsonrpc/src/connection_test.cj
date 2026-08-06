package jsonrpc

import std.collection.concurrent.*
import std.sync.AtomicBool
import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.*
import stdx.serialization.serialization.*
import stdxx.*

func boolOf(dm: DataModel): Bool {
    (dm as DataModelBool).getOrThrow().getValue()
}

func emptyParams(): ArrayOrObject {
    ArrayOrObject.Object(DataModelStruct())
}

/**
 * What the fake hands the read loop next. `Undecodable` is the frame that arrived
 * intact but failed to parse - the case `JsonRpcTransport.read` reports with an
 * `RpcException` while leaving the stream in sync behind it.
 */
enum Frame {
    | Decoded(Body)
    | Undecodable(RpcException)
    | Eof
}

/**
 * An in-memory `Transport` the test drives by hand: `read` blocks until a frame is
 * fed, and every written body queues up for inspection. A `ByteBuffer`-backed
 * `JsonRpcTransport` cannot stand in here - it reports EOF the moment it runs dry,
 * so it could never answer a request that has not been sent yet.
 */
class FakeTransport <: JsonRpcTransport {
    private let inbound = LinkedBlockingQueue<Frame>()
    private let written = LinkedBlockingQueue<Body>()
    private let closed = AtomicBool(false)

    func feed(body: Body): Unit {
        inbound.add(Decoded(body))
    }

    func feedUndecodable(e: RpcException): Unit {
        inbound.add(Undecodable(e))
    }

    func hangUp(): Unit {
        inbound.add(Eof)
    }

    /**
     * Blocks until the connection writes, so no test has to poll a spawned handler.
     */
    func nextWritten(): Body {
        written.remove()
    }

    public func isClosed(): Bool {
        closed.load()
    }

    /**
     * Feeds an EOF as it closes, standing in for the real transport's blocked read
     * failing the moment its stream is torn away.
     */
    public func close(): Unit {
        if (!closed.swap(true)) {
            inbound.add(Eof)
        }
    }

    public func read(): ?Body {
        if (isClosed()) {
            return None
        }
        match (inbound.remove()) {
            case Decoded(body) => body
            case Undecodable(e) => throw e
            case Eof => None
        }
    }

    public func write(body: Body): Unit {
        if (isClosed()) {
            throw TransportException("fake transport is closed")
        }
        written.add(body)
    }
}

/**
 * A `Handler` whose behaviour each test supplies as a lambda. Handled notification
 * methods are recorded on a blocking queue so a test can wait for one to land
 * instead of sleeping.
 */
class FakeHandler <: Handler {
    var onRequestFn: (String, ?ArrayOrObject, CancellationToken) -> ResultOrError = {
        _, _, _ => Result(DataModelNull())
    }
    var onNotificationFn: (String, ?ArrayOrObject) -> Unit = {_, _ => ()}

    let notified = LinkedBlockingQueue<String>()

    public func onRequest(method: String, params: ?ArrayOrObject, cancel: CancellationToken): ResultOrError {
        onRequestFn(method, params, cancel)
    }

    public func onNotification(method: String, params: ?ArrayOrObject): Unit {
        // recorded before the call, so a throwing handler is still observable
        notified.add(method)
        onNotificationFn(method, params)
    }
}

/**
 * `serve` blocks on the read queue, so every test runs it off-thread and talks to
 * the connection through the fake's queues.
 */
func serving(handler: FakeHandler): (Connection, FakeTransport) {
    let transport = FakeTransport()
    let connection = Connection(transport, handler, getGlobalLogger())
    spawn {connection.serve()}
    (connection, transport)
}

@Test
class ConnectionServeRequestTest {
    @TestCase
    func serveAnswersARequestWithTheHandlerResult() {
        // arrange
        let handler = FakeHandler()
        handler.onRequestFn = {_, _, _ => Result(DataModelInt(42))}
        let (_, transport) = serving(handler)

        // act
        transport.feed(RequestBody(Integer(1), "initialize").enveloped())
        let resp = transport.nextWritten().getResponseBodyOrThrow()

        // assert - the response carries the id it was asked under
        @Expect(Integer(1), resp.id.getOrThrow())
        @Expect(42, resp.resultOrError.getResultOrThrow().asIntOrThrow())
    }

    @TestCase
    func serveHandsTheMethodAndParamsToTheHandler() {
        // arrange
        let handler = FakeHandler()
        handler.onRequestFn = {
            method, params, _ => Result(DataModelString("${method}:${fieldOf(params, "processId").asIntOrThrow()}"))
        }
        let (_, transport) = serving(handler)
        let params = ArrayOrObject.Object(DataModelStruct().add(field("processId", 42)))

        // act
        transport.feed(RequestBody(Integer(1), "initialize", params: params).enveloped())
        let resp = transport.nextWritten().getResponseBodyOrThrow()

        // assert
        @Expect("initialize:42", resp.resultOrError.getResultOrThrow().asStringOrThrow())
    }

    @TestCase
    func serveSendsBackAnErrorTheHandlerReturned() {
        // arrange - the ordinary failure path: a router that cannot place a method
        // says so with a value, no stack unwinding involved
        let handler = FakeHandler()
        handler.onRequestFn = {
            method, _, _ => ResultOrError.Error(ResponseError(ErrorCode.METHOD_NOT_FOUND, "no such method: ${method}"))
        }
        let (_, transport) = serving(handler)

        // act
        transport.feed(RequestBody(Integer(1), "nope").enveloped())
        let resp = transport.nextWritten().getResponseBodyOrThrow()

        // assert - the error goes out under the request's own id
        @Expect(Integer(1), resp.id.getOrThrow())
        @Expect(ErrorCode.METHOD_NOT_FOUND, resp.resultOrError.getErrorOrThrow().code)
        @Expect("no such method: nope", resp.resultOrError.getErrorOrThrow().message)
    }

    @TestCase
    func serveTurnsAnRpcExceptionIntoThatSameError() {
        // arrange - throwing stays supported for a bail-out deep in a call chain,
        // where returning an error is not reachable
        let handler = FakeHandler()
        handler.onRequestFn = {
            method, _, _ => throw RpcException(ErrorCode.METHOD_NOT_FOUND, "no such method: ${method}")
        }
        let (_, transport) = serving(handler)

        // act
        transport.feed(RequestBody(Integer(1), "nope").enveloped())
        let err = transport.nextWritten().getResponseBodyOrThrow().resultOrError.getErrorOrThrow()

        // assert
        @Expect(ErrorCode.METHOD_NOT_FOUND, err.code)
        @Expect("no such method: nope", err.message)
    }

    @TestCase
    func serveTurnsAnUnexpectedExceptionIntoAnInternalError() {
        // arrange - a handler bug is not a protocol error, but it still owes the
        // peer a response rather than silence
        let handler = FakeHandler()
        handler.onRequestFn = {_, _, _ => throw IllegalStateException("handler blew up")}
        let (_, transport) = serving(handler)

        // act
        transport.feed(RequestBody(Integer(1), "initialize").enveloped())
        let err = transport.nextWritten().getResponseBodyOrThrow().resultOrError.getErrorOrThrow()

        // assert
        @Expect(ErrorCode.INTERNAL_ERROR, err.code)
        @Expect("handler blew up", err.message)
    }

    @TestCase
    func serveRejectsARequestIdThatIsAlreadyInFlight() {
        // arrange - the first request parks inside the handler, so the duplicate
        // arrives while id 1 is still registered
        let started = LinkedBlockingQueue<Bool>()
        let release = LinkedBlockingQueue<Bool>()
        let handler = FakeHandler()
        handler.onRequestFn = {
            _, _, _ =>
                started.add(true)
                release.remove()
                Result(DataModelInt(42))
        }
        let (_, transport) = serving(handler)

        // act
        transport.feed(RequestBody(Integer(1), "slow").enveloped())
        started.remove() // the handler is in, so the id is registered
        transport.feed(RequestBody(Integer(1), "slow").enveloped())
        let rejected = transport.nextWritten().getResponseBodyOrThrow()
        release.add(true)
        let completed = transport.nextWritten().getResponseBodyOrThrow()

        // assert - the duplicate is refused and the original still answers, rather
        // than the two silently sharing one cancellation token
        @Expect(ErrorCode.INVALID_REQUEST, rejected.resultOrError.getErrorOrThrow().code)
        @Expect(42, completed.resultOrError.getResultOrThrow().asIntOrThrow())
    }

    @TestCase
    func serveReusesAnIdOnceItsRequestHasFinished() {
        // arrange - the duplicate check must not turn ids into a one-shot resource
        let handler = FakeHandler()
        handler.onRequestFn = {_, _, _ => Result(DataModelInt(42))}
        let (_, transport) = serving(handler)

        // act
        transport.feed(RequestBody(Integer(1), "initialize").enveloped())
        let first = transport.nextWritten().getResponseBodyOrThrow()
        transport.feed(RequestBody(Integer(1), "initialize").enveloped())
        let second = transport.nextWritten().getResponseBodyOrThrow()

        // assert
        @Expect(42, first.resultOrError.getResultOrThrow().asIntOrThrow())
        @Expect(42, second.resultOrError.getResultOrThrow().asIntOrThrow())
    }
}

@Test
class ConnectionServeNotificationTest {
    @TestCase
    func serveRoutesANotificationToTheHandler() {
        // arrange
        let handler = FakeHandler()
        let (_, transport) = serving(handler)

        // act
        transport.feed(NotificationBody("exit").enveloped())

        // assert
        @Expect("exit", handler.notified.remove())
    }

    @TestCase
    func serveNeverAnswersANotification() {
        // arrange
        let handler = FakeHandler()
        let (_, transport) = serving(handler)

        // act - a notification, then a request; the request's response must be the
        // first thing on the wire, which it cannot be if the notification answered
        transport.feed(NotificationBody("initialized").enveloped())
        @Expect("initialized", handler.notified.remove())
        transport.feed(RequestBody(Integer(1), "shutdown").enveloped())
        let written = transport.nextWritten().getResponseBodyOrThrow()

        // assert
        @Expect(Integer(1), written.id.getOrThrow())
    }

    @TestCase
    func serveSurvivesAFailingNotificationHandler() {
        // arrange - nobody is waiting on a notification's outcome, so a throwing
        // handler must neither answer the peer nor stop the connection
        let handler = FakeHandler()
        handler.onRequestFn = {_, _, _ => Result(DataModelInt(42))}
        handler.onNotificationFn = {
            method, _ => if (method == "boom") {
                throw IllegalStateException("handler blew up")
            }
        }
        let (_, transport) = serving(handler)

        // act - wait for the failure to happen, then ask a question that must be
        // answered; its response is the first frame on the wire, or the failure
        // wrote something of its own
        transport.feed(NotificationBody("boom").enveloped())
        @Expect("boom", handler.notified.remove())
        transport.feed(RequestBody(Integer(1), "initialize").enveloped())
        let written = transport.nextWritten().getResponseBodyOrThrow()

        // assert
        @Expect(Integer(1), written.id.getOrThrow())
        @Expect(42, written.resultOrError.getResultOrThrow().asIntOrThrow())
    }
}

@Test
class ConnectionServeRecoveryTest {
    @TestCase
    func serveAnswersAnUndecodableFrameAndKeepsReading() {
        // arrange - `RpcException` from the transport means the payload was junk but
        // the framing held, so there is a next message to find
        let handler = FakeHandler()
        let (_, transport) = serving(handler)

        // act
        transport.feedUndecodable(RpcException(ErrorCode.PARSE_ERROR, "JSON-RPC content is not valid JSON"))
        let resp = transport.nextWritten().getResponseBodyOrThrow()
        transport.feed(NotificationBody("exit").enveloped())

        // assert - the error goes out under a null id, since the frame never got far
        // enough to have one, and the loop reads on
        @Assert(resp.id.isNull())
        @Expect(ErrorCode.PARSE_ERROR, resp.resultOrError.getErrorOrThrow().code)
        @Expect("exit", handler.notified.remove())
    }

    @TestCase
    func serveReturnsOnCleanEof() {
        // arrange
        let transport = FakeTransport()
        let connection = Connection(transport, FakeHandler(), getGlobalLogger())

        // act - on the test's own thread: it returns, or the test hangs
        transport.hangUp()
        connection.serve()

        // assert
    }

    @TestCase
    func serveDropsAResponseNobodyIsWaitingFor() {
        // arrange
        let handler = FakeHandler()
        let (_, transport) = serving(handler)

        // act - an id we never sent, then a frame that proves the loop is alive
        transport.feed(ResponseBody.result(Value(Integer(999)), DataModelInt(1)).enveloped())
        transport.feed(NotificationBody("exit").enveloped())

        // assert
        @Expect("exit", handler.notified.remove())
    }

    @TestCase
    func serveDropsAResponseWithANullId() {
        // arrange - the peer rejecting a frame it could not identify: there is
        // nothing to correlate it against, but it must not stall the loop
        let handler = FakeHandler()
        let (_, transport) = serving(handler)

        // act
        transport.feed(ResponseBody.error(Null, ResponseError(ErrorCode.PARSE_ERROR, "not valid JSON")).enveloped())
        transport.feed(NotificationBody("exit").enveloped())

        // assert
        @Expect("exit", handler.notified.remove())
    }
}

@Test
class ConnectionCancelTest {
    @TestCase
    func cancelReachesTheHandlerOfTheInFlightRequest() {
        // arrange - the handler parks until the test has cancelled, then reports
        // what its token says
        let started = LinkedBlockingQueue<Bool>()
        let release = LinkedBlockingQueue<Bool>()
        let handler = FakeHandler()
        handler.onRequestFn = {
            _, _, cancel =>
                started.add(true)
                release.remove()
                Result(DataModelBool(cancel.isCancelled))
        }
        let (connection, transport) = serving(handler)

        // act
        transport.feed(RequestBody(Integer(7), "slow").enveloped())
        started.remove()
        connection.cancel(Integer(7))
        release.add(true)
        let resp = transport.nextWritten().getResponseBodyOrThrow()

        // assert
        @Assert(boolOf(resp.resultOrError.getResultOrThrow()))
    }

    @TestCase
    func cancelIgnoresAnIdThatIsNotInFlight() {
        // arrange
        let handler = FakeHandler()
        handler.onRequestFn = {_, _, cancel => Result(DataModelBool(cancel.isCancelled))}
        let (connection, transport) = serving(handler)

        // act - cancelling an unknown id is a no-op, and must not poison the id for
        // a later request that legitimately uses it
        connection.cancel(Integer(404))
        transport.feed(RequestBody(Integer(404), "initialize").enveloped())
        let resp = transport.nextWritten().getResponseBodyOrThrow()

        // assert
        @Assert(!boolOf(resp.resultOrError.getResultOrThrow()))
    }
}

@Test
class ConnectionOutboundTest {
    @TestCase
    func requestWritesTheFrameAndSequencesIds() {
        // arrange
        let transport = FakeTransport()
        let connection = Connection(transport, FakeHandler(), getGlobalLogger())

        // act
        let first = connection.request<ArrayOrObject, ArrayOrObject>("window/showMessageRequest", emptyParams())
        let second = connection.request<ArrayOrObject, ArrayOrObject>("window/showMessageRequest", emptyParams())

        // assert - ids come off our own counter, so they are distinct
        @Expect(Integer(0), first.id)
        @Expect(Integer(1), second.id)
        @Expect("window/showMessageRequest", transport.nextWritten().getRequestBodyOrThrow().method)
    }

    @TestCase
    func awaitReturnsTheResultOfTheMatchingResponse() {
        // arrange
        let transport = FakeTransport()
        let connection = Connection(transport, FakeHandler(), getGlobalLogger())
        spawn {connection.serve()}

        // act
        let pending = connection.request<ArrayOrObject, Int64>("workspace/configuration", emptyParams())
        transport.nextWritten()
        transport.feed(ResponseBody.result(Value(pending.id), DataModelInt(7)).enveloped())

        // assert
        @Expect(7, pending.await())
    }

    @TestCase
    func awaitThrowsWhenThePeerAnswersWithAnError() {
        // arrange - an error response has to reach the caller as a throw; there is
        // no result to hand back and no thread of ours to swallow it
        let transport = FakeTransport()
        let connection = Connection(transport, FakeHandler(), getGlobalLogger())
        spawn {connection.serve()}

        // act
        let pending = connection.request<ArrayOrObject, Int64>("workspace/configuration", emptyParams())
        transport.nextWritten()
        transport.feed(
            ResponseBody.error(Value(pending.id), ResponseError(ErrorCode.INVALID_PARAMS, "bad params")).enveloped())

        // assert
        let e = @AssertThrows[RpcException](pending.await())
        @Expect(ErrorCode.INVALID_PARAMS, e.code)
        @Expect("bad params", e.message)
    }

    @TestCase
    func awaitCorrelatesByIdNotArrivalOrder() {
        // arrange - the whole point of the pending map: a slow first request must
        // not hold up an answer that already arrived for the second
        let transport = FakeTransport()
        let connection = Connection(transport, FakeHandler(), getGlobalLogger())
        spawn {connection.serve()}

        // act
        let first = connection.request<ArrayOrObject, Int64>("first", emptyParams())
        let second = connection.request<ArrayOrObject, Int64>("second", emptyParams())
        transport.nextWritten()
        transport.nextWritten()
        transport.feed(ResponseBody.result(Value(second.id), DataModelInt(2)).enveloped())
        transport.feed(ResponseBody.result(Value(first.id), DataModelInt(1)).enveloped())

        // assert
        @Expect(2, second.await())
        @Expect(1, first.await())
    }

    @TestCase
    func awaitWithTimeoutReturnsAResultThatArrivesInTime() {
        // arrange
        let transport = FakeTransport()
        let connection = Connection(transport, FakeHandler(), getGlobalLogger())
        spawn {connection.serve()}

        // act - the answer is already queued, so the timeout is never approached
        let pending = connection.request<ArrayOrObject, Int64>("workspace/configuration", emptyParams())
        transport.nextWritten()
        transport.feed(ResponseBody.result(Value(pending.id), DataModelInt(7)).enveloped())

        // assert
        @Expect(7, pending.await(timeout: Duration.second).getOrThrow())
    }

    @TestCase
    func aTimedOutRequestDropsItsLateResponse() {
        // arrange
        let handler = FakeHandler()
        let (connection, transport) = serving(handler)

        // act - give up, then let the answer turn up anyway
        let pending = connection.request<ArrayOrObject, Int64>("workspace/configuration", emptyParams())
        transport.nextWritten()
        let timedOut = pending.await(timeout: Duration.millisecond * 50)
        transport.feed(ResponseBody.result(Value(pending.id), DataModelInt(7)).enveloped())
        transport.feed(NotificationBody("exit").enveloped())

        // assert - giving up unregistered the id, so the late answer is dropped like
        // any other uncorrelated response instead of holding its slot forever
        @Assert(timedOut.isNone())
        @Expect("exit", handler.notified.remove())
    }

    @TestCase
    func notifyWritesTheFrameWithItsParams() {
        // arrange
        let transport = FakeTransport()
        let connection = Connection(transport, FakeHandler(), getGlobalLogger())
        let params = ArrayOrObject.Object(DataModelStruct().add(field("message", "hi")))

        // act
        connection.notify("window/logMessage", params)
        let note = transport.nextWritten().getNotificationBodyOrThrow()

        // assert
        @Expect("window/logMessage", note.method)
        @Expect("hi", fieldOf(note.params, "message").asStringOrThrow())
    }

    @TestCase
    func notifyOmitsParamsThatSerializeToNull() {
        // arrange - "no params" is an absent key, never an explicit null
        let transport = FakeTransport()
        let connection = Connection(transport, FakeHandler(), getGlobalLogger())

        // act
        connection.notify("exit", Nullable<Int32>.Null)
        let note = transport.nextWritten().getNotificationBodyOrThrow()

        // assert
        @Assert(note.params.isNone())
    }

    @TestCase
    func notifyRejectsParamsThatAreNeitherArrayNorObject() {
        // arrange - JSON-RPC params are structured; a bare scalar has no encoding
        let transport = FakeTransport()
        let connection = Connection(transport, FakeHandler(), getGlobalLogger())

        // act
        let e = @AssertThrows[RpcException](connection.notify("window/logMessage", 42i32))

        // assert
        @Expect(ErrorCode.INVALID_PARAMS, e.code)
    }
}

@Test
class ConnectionCloseTest {
    @TestCase
    func closeEndsAServeLoopBlockedOnARead() {
        // arrange - nothing is ever fed, so the loop can only end by being closed
        let transport = FakeTransport()
        let connection = Connection(transport, FakeHandler(), getGlobalLogger())
        let returned = LinkedBlockingQueue<Bool>()
        spawn {
            =>
                connection.serve()
                returned.add(true)
        }

        // act
        connection.close()

        // assert
        @Assert(returned.remove(Duration.second * 5) ?? false)
        @Assert(connection.isClosed())
    }

    @TestCase
    func closeWakesACallerWaitingForAnAnswer() {
        // arrange - the peer will never answer, and a caller blocked in `await` has
        // no timeout of its own to save it
        let (connection, transport) = serving(FakeHandler())
        let pending = connection.request<ArrayOrObject, Int64>("workspace/configuration", emptyParams())
        transport.nextWritten()

        // act
        connection.close()

        // assert - the wait ends as a throw, not as a wait that never ends
        let e = @AssertThrows[RpcException](pending.await())
        @Expect(ErrorCode.INTERNAL_ERROR, e.code)
    }

    @TestCase
    func aPeerHangUpWakesACallerWaitingForAnAnswer() {
        // arrange - same dangling wait, reached from the other side: EOF ends the
        // read loop, so nothing will ever fill the slot
        let (connection, transport) = serving(FakeHandler())
        let pending = connection.request<ArrayOrObject, Int64>("workspace/configuration", emptyParams())
        transport.nextWritten()

        // act
        transport.hangUp()

        // assert
        let e = @AssertThrows[RpcException](pending.await())
        @Expect(ErrorCode.INTERNAL_ERROR, e.code)
    }

    @TestCase
    func closeTellsInFlightHandlersToGiveUp() {
        // arrange - the handler parks mid-request, the way a slow one would
        let started = LinkedBlockingQueue<CancellationToken>()
        let release = LinkedBlockingQueue<Bool>()
        let handler = FakeHandler()
        handler.onRequestFn = {
            _, _, cancel =>
                started.add(cancel)
                release.remove()
                Result(DataModelNull())
        }
        let (connection, transport) = serving(handler)
        transport.feed(RequestBody(Integer(7), "slow").enveloped())
        let token = started.remove()

        // act - no response of the handler's can reach the peer any more, so it is
        // told to stop rather than left running against a dead connection
        connection.close()
        release.add(true)

        // assert
        @Assert(token.isCancelled)
    }

    @TestCase
    func closeRejectsFurtherWrites() {
        // arrange
        let transport = FakeTransport()
        let connection = Connection(transport, FakeHandler(), getGlobalLogger())

        // act
        connection.close()

        // assert
        @AssertThrows[TransportException](connection.notify("window/logMessage", emptyParams()))
    }

    @TestCase
    func closeIsIdempotent() {
        // arrange - shutdown paths overlap: `serve` unwinding and an explicit close
        // can both land, and a second close must not throw
        let transport = FakeTransport()
        let connection = Connection(transport, FakeHandler(), getGlobalLogger())

        // act
        connection.close()
        connection.close()

        // assert
        @Assert(connection.isClosed())
    }
}
