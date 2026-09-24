package jsonrpc

import std.collection.concurrent.*
import std.sync.AtomicBool
import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.*
import stdx.serialization.serialization.*
import stdxx.*

func emptyParams(): ArrayOrObject {
    ArrayOrObject.Object(DataModelStruct())
}

func answer(id: RequestId, result: DataModel): Body {
    ResponseBody(Value(id), Result(result)).enveloped()
}

/**
 * What the fake hands the read loop next: `Undecodable` is a frame that arrived intact but did
 * not decode, which leaves the stream in sync behind it.
 */
enum Frame {
    | Decoded(Body)
    | Undecodable(RpcException)
    | Eof
}

/**
 * `read` blocks until the test feeds a frame, and every written body queues up for inspection.
 * A `ByteBuffer`-backed transport reports EOF the moment it runs dry, so it could never answer
 * a request that has not been sent yet.
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
     * Feeds an EOF, as the real transport's blocked read fails the moment its stream is torn away.
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
 * Behaves as each test's lambdas say. Requests are answered from a thread of the handler's own
 * unless `inPlace` is set, since a test that parks a handler would otherwise park the read loop
 * with it. Notification methods are recorded so a test can wait for one to land.
 */
class FakeHandler <: Handler {
    var onRequestFn: (String, ?ArrayOrObject, CancellationToken) -> ResultOrError = {
        _, _, _ => Result(DataModelNull())
    }
    var onNotificationFn: (String, ?ArrayOrObject) -> Unit = {_, _ => ()}
    var inPlace = false

    let notified = LinkedBlockingQueue<String>()

    public func onRequest(request: InboundRequest): Unit {
        if (inPlace) {
            request.respond(onRequestFn(request.method, request.params, request.cancellation))
            return
        }
        spawn {
            request.respondWith {=> onRequestFn(request.method, request.params, request.cancellation)}
        }
    }

    public func onNotification(method: String, params: ?ArrayOrObject): Unit {
        // recorded first, so a throwing handler is still observable
        notified.add(method)
        onNotificationFn(method, params)
    }
}

/**
 * Keeps every request unanswered, so a test can answer it by hand, whenever and however often.
 */
class KeepingHandler <: Handler {
    let received = LinkedBlockingQueue<InboundRequest>()

    public func onRequest(request: InboundRequest): Unit {
        received.add(request)
    }

    public func onNotification(method: String, params: ?ArrayOrObject): Unit {}
}

class AnswerThenThrowHandler <: Handler {
    public func onRequest(request: InboundRequest): Unit {
        request.respond(Result(DataModelInt(42)))
        throw IllegalStateException("too late to matter")
    }

    public func onNotification(method: String, params: ?ArrayOrObject): Unit {}
}

func serving(handler: Handler): (Connection, FakeTransport) {
    let transport = FakeTransport()
    let connection = Connection(transport, handler, getGlobalLogger())
    spawn {connection.serve()}
    (connection, transport)
}

@Test
class ConnectionServeRequestTest {
    @TestCase
    func aRequestIsAnsweredUnderItsIdWithWhatTheHandlerGives() {
        // arrange
        let handler = FakeHandler()
        handler.onRequestFn = {
            method, params, _ => Result(DataModelString("${method}:${fieldOf(params, "a").asIntOrThrow()}"))
        }
        let (_, transport) = serving(handler)
        let params = ArrayOrObject.Object(DataModelStruct().add(field("a", 42)))

        // act
        transport.feed(RequestBody(Integer(1), "m", params: params).enveloped())
        let resp = transport.nextWritten().getResponseBodyOrThrow()

        // assert
        @Expect(Integer(1), resp.id.getOrThrow())
        @Expect("m:42", resp.resultOrError.getResultOrThrow().asStringOrThrow())
    }

    @TestCase[inPlace in [ false, true ]]
    func aThrowingHandlerIsAnsweredWithTheErrorItStandsFor(inPlace: Bool) {
        // arrange - a spawned handler throws inside `respondWith`, one in place out of
        // `onRequest`, where the connection answers for it
        let handler = FakeHandler()
        handler.inPlace = inPlace
        handler.onRequestFn = {
            method, _, _ => if (method == "rpc") {
                throw RpcException(ErrorCode.METHOD_NOT_FOUND, "no such method")
            } else {
                throw IllegalStateException("handler blew up")
            }
        }
        let (_, transport) = serving(handler)

        // act
        transport.feed(RequestBody(Integer(1), "rpc").enveloped())
        let rpc = transport.nextWritten().getResponseBodyOrThrow()
        transport.feed(RequestBody(Integer(2), "bug").enveloped())
        let bug = transport.nextWritten().getResponseBodyOrThrow()

        // assert
        @Expect(Integer(1), rpc.id.getOrThrow())
        @Expect(ErrorCode.METHOD_NOT_FOUND, rpc.resultOrError.getErrorOrThrow().code)
        @Expect(Integer(2), bug.id.getOrThrow())
        @Expect(ErrorCode.INTERNAL_ERROR, bug.resultOrError.getErrorOrThrow().code)
        @Expect("handler blew up", bug.resultOrError.getErrorOrThrow().message)
    }

    @TestCase
    func aRequestIdAlreadyInFlightIsRefused() {
        // arrange - the first request parks inside the handler, so its id is still registered
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
        started.remove()
        transport.feed(RequestBody(Integer(1), "slow").enveloped())
        let rejected = transport.nextWritten().getResponseBodyOrThrow()
        release.add(true)
        let completed = transport.nextWritten().getResponseBodyOrThrow()

        // assert - rather than the two sharing one cancellation token
        @Expect(ErrorCode.INVALID_REQUEST, rejected.resultOrError.getErrorOrThrow().code)
        @Expect(42, completed.resultOrError.getResultOrThrow().asIntOrThrow())
    }

    @TestCase
    func anIdCanBeReusedOnceItsRequestIsAnswered() {
        // arrange
        let handler = FakeHandler()
        handler.onRequestFn = {_, _, _ => Result(DataModelInt(42))}
        let (_, transport) = serving(handler)

        // act
        transport.feed(RequestBody(Integer(1), "m").enveloped())
        let first = transport.nextWritten().getResponseBodyOrThrow()
        transport.feed(RequestBody(Integer(1), "m").enveloped())
        let second = transport.nextWritten().getResponseBodyOrThrow()

        // assert
        @Expect(42, first.resultOrError.getResultOrThrow().asIntOrThrow())
        @Expect(42, second.resultOrError.getResultOrThrow().asIntOrThrow())
    }
}

@Test
class ConnectionServeNotificationTest {
    @TestCase
    func aNotificationReachesTheHandlerAndIsNeverAnswered() {
        // arrange
        let handler = FakeHandler()
        let (_, transport) = serving(handler)

        // act - the request's answer is the first frame out only if the notification wrote none
        transport.feed(NotificationBody("note").enveloped())
        @Expect("note", handler.notified.remove())
        transport.feed(RequestBody(Integer(1), "m").enveloped())
        let written = transport.nextWritten().getResponseBodyOrThrow()

        // assert
        @Expect(Integer(1), written.id.getOrThrow())
    }

    @TestCase
    func aFailingNotificationHandlerNeitherAnswersNorStopsTheLoop() {
        // arrange
        let handler = FakeHandler()
        handler.onRequestFn = {_, _, _ => Result(DataModelInt(42))}
        handler.onNotificationFn = {_, _ => throw IllegalStateException("handler blew up")}
        let (_, transport) = serving(handler)

        // act
        transport.feed(NotificationBody("boom").enveloped())
        @Expect("boom", handler.notified.remove())
        transport.feed(RequestBody(Integer(1), "m").enveloped())
        let written = transport.nextWritten().getResponseBodyOrThrow()

        // assert
        @Expect(Integer(1), written.id.getOrThrow())
        @Expect(42, written.resultOrError.getResultOrThrow().asIntOrThrow())
    }
}

@Test
class ConnectionDeliveryOrderTest {
    @TestCase
    func messagesReachTheHandlerInTheOrderTheyArrived() {
        // arrange - requests answered in place log into the notifications' queue, so the queue
        // is the order the handler saw them in
        let handler = FakeHandler()
        handler.inPlace = true
        handler.onRequestFn = {
            method, _, _ =>
                handler.notified.add(method)
                Result(DataModelNull())
        }
        let (_, transport) = serving(handler)
        let methods = ["note1", "request1", "note2", "note3", "request2", "note4"]

        // act
        for (i in 0..methods.size) {
            if (methods[i].startsWith("request")) {
                transport.feed(RequestBody(Integer(Int32(i)), methods[i]).enveloped())
            } else {
                transport.feed(NotificationBody(methods[i]).enveloped())
            }
        }

        // assert
        for (method in methods) {
            @Expect(method, handler.notified.remove())
        }
    }

    @TestCase
    func aRequestCanBeAnsweredAfterItsHandlerReturned() {
        // arrange
        let handler = KeepingHandler()
        let (_, transport) = serving(handler)
        transport.feed(RequestBody(Integer(1), "slow").enveloped())
        let request = handler.received.remove()

        // act
        @Assert(!request.isAnswered)
        request.respond(Result(DataModelInt(42)))
        let resp = transport.nextWritten().getResponseBodyOrThrow()

        // assert
        @Expect(Integer(1), resp.id.getOrThrow())
        @Expect(42, resp.resultOrError.getResultOrThrow().asIntOrThrow())
    }

    @TestCase
    func onlyTheFirstAnswerReachesThePeer() {
        // arrange
        let handler = KeepingHandler()
        let (_, transport) = serving(handler)
        transport.feed(RequestBody(Integer(1), "twice").enveloped())
        let request = handler.received.remove()

        // act
        let first = request.respond(Result(DataModelInt(1)))
        let second = request.respond(Result(DataModelInt(2)))
        transport.feed(RequestBody(Integer(2), "next").enveloped())
        handler.received.remove().respond(Result(DataModelInt(3)))

        // assert - the frame after the first answer is the next request's
        @Assert(first)
        @Assert(!second)
        @Expect(1, transport.nextWritten().getResponseBodyOrThrow().resultOrError.getResultOrThrow().asIntOrThrow())
        @Expect(Integer(2), transport.nextWritten().getResponseBodyOrThrow().id.getOrThrow())
    }

    @TestCase
    func aThrowAfterAnsweringLeavesTheAnswerAlone() {
        // arrange
        let (_, transport) = serving(AnswerThenThrowHandler())

        // act
        transport.feed(RequestBody(Integer(1), "m").enveloped())
        transport.feed(RequestBody(Integer(2), "m").enveloped())
        let first = transport.nextWritten().getResponseBodyOrThrow()
        let second = transport.nextWritten().getResponseBodyOrThrow()

        // assert - no fallback error followed the first answer out
        @Expect(42, first.resultOrError.getResultOrThrow().asIntOrThrow())
        @Expect(Integer(2), second.id.getOrThrow())
    }

    @TestCase
    func anAnswerOnAClosedConnectionIsDroppedQuietly() {
        // arrange - a handler thread finishing after shutdown has nobody above it to catch a throw
        let handler = KeepingHandler()
        let (connection, transport) = serving(handler)
        transport.feed(RequestBody(Integer(1), "slow").enveloped())
        let request = handler.received.remove()

        // act
        connection.close()
        request.respond(Result(DataModelInt(42)))

        // assert
        @Assert(request.cancellation.isCancelled)
    }
}

@Test
class ConnectionServeRecoveryTest {
    @TestCase
    func anUndecodableFrameIsAnsweredAndTheLoopReadsOn() {
        // arrange
        let handler = FakeHandler()
        let (_, transport) = serving(handler)

        // act
        transport.feedUndecodable(RpcException(ErrorCode.PARSE_ERROR, "not valid JSON"))
        let resp = transport.nextWritten().getResponseBodyOrThrow()
        transport.feed(NotificationBody("next").enveloped())

        // assert
        @Assert(resp.id.isNull())
        @Expect(ErrorCode.PARSE_ERROR, resp.resultOrError.getErrorOrThrow().code)
        @Expect("next", handler.notified.remove())
    }

    @TestCase
    func serveReturnsOnCleanEof() {
        // arrange
        let transport = FakeTransport()
        let connection = Connection(transport, FakeHandler(), getGlobalLogger())

        // act & assert - on the test's own thread: it returns, or the test hangs
        transport.hangUp()
        connection.serve()
    }

    @TestCase[id in [ Nullable<RequestId>.Value(Integer(999)), Nullable<RequestId>.Null ]]
    func aResponseNobodyWaitsForIsDropped(id: Nullable<RequestId>) {
        // arrange - an id never sent, and a null one the peer could not tie to any frame of ours
        let handler = FakeHandler()
        let (_, transport) = serving(handler)

        // act
        transport.feed(ResponseBody(id, ResultOrError.Error(ResponseError(ErrorCode.PARSE_ERROR, "x"))).enveloped())
        transport.feed(NotificationBody("next").enveloped())

        // assert - the loop is still alive
        @Expect("next", handler.notified.remove())
    }
}

@Test
class ConnectionCancelTest {
    @TestCase
    func cancelReachesTheHandlerOfTheInFlightRequest() {
        // arrange - the handler parks until the test has cancelled, then reports its token
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
        @Assert(resp.resultOrError.getResultOrThrow().asBoolOrThrow())
    }

    @TestCase
    func cancelOfAnIdNotInFlightDoesNotPoisonIt() {
        // arrange
        let handler = FakeHandler()
        handler.onRequestFn = {_, _, cancel => Result(DataModelBool(cancel.isCancelled))}
        let (connection, transport) = serving(handler)

        // act
        connection.cancel(Integer(404))
        transport.feed(RequestBody(Integer(404), "m").enveloped())
        let resp = transport.nextWritten().getResponseBodyOrThrow()

        // assert
        @Assert(!resp.resultOrError.getResultOrThrow().asBoolOrThrow())
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
        let first = connection.request<ArrayOrObject, ArrayOrObject>("ask", emptyParams())
        let second = connection.request<ArrayOrObject, ArrayOrObject>("ask", emptyParams())

        // assert
        @Expect(Integer(0), first.id)
        @Expect(Integer(1), second.id)
        @Expect("ask", transport.nextWritten().getRequestBodyOrThrow().method)
    }

    @TestCase
    func awaitCorrelatesByIdNotArrivalOrder() {
        // arrange
        let (connection, transport) = serving(FakeHandler())

        // act
        let first = connection.request<ArrayOrObject, Int64>("first", emptyParams())
        let second = connection.request<ArrayOrObject, Int64>("second", emptyParams())
        transport.nextWritten()
        transport.nextWritten()
        transport.feed(answer(second.id, DataModelInt(2)))
        transport.feed(answer(first.id, DataModelInt(1)))

        // assert
        @Expect(2, second.await())
        @Expect(1, first.await())
    }

    @TestCase
    func awaitThrowsWhenThePeerAnswersWithAnError() {
        // arrange
        let (connection, transport) = serving(FakeHandler())

        // act
        let pending = connection.request<ArrayOrObject, Int64>("ask", emptyParams())
        transport.nextWritten()
        transport.feed(
            ResponseBody(Value(pending.id), ResultOrError.Error(ResponseError(ErrorCode.INVALID_PARAMS, "bad params")))
                .enveloped())

        // assert
        let e = @AssertThrows[RpcException](pending.await())
        @Expect(ErrorCode.INVALID_PARAMS, e.code)
        @Expect("bad params", e.message)
    }

    @TestCase
    func awaitWithTimeoutReturnsAResultThatArrivesInTime() {
        // arrange
        let (connection, transport) = serving(FakeHandler())

        // act
        let pending = connection.request<ArrayOrObject, Int64>("ask", emptyParams())
        transport.nextWritten()
        transport.feed(answer(pending.id, DataModelInt(7)))

        // assert
        @Expect(7, pending.await(timeout: Duration.second).getOrThrow())
    }

    @TestCase
    func aTimedOutRequestDropsItsLateResponse() {
        // arrange
        let handler = FakeHandler()
        let (connection, transport) = serving(handler)

        // act
        let pending = connection.request<ArrayOrObject, Int64>("ask", emptyParams())
        transport.nextWritten()
        let timedOut = pending.await(timeout: Duration.millisecond * 50)
        transport.feed(answer(pending.id, DataModelInt(7)))
        transport.feed(NotificationBody("next").enveloped())

        // assert - dropped as any uncorrelated response is, and the loop is still alive
        @Assert(timedOut.isNone())
        @Expect("next", handler.notified.remove())
    }

    @TestCase
    func notifyWritesTheFrameWithItsParams() {
        // arrange
        let transport = FakeTransport()
        let connection = Connection(transport, FakeHandler(), getGlobalLogger())
        let params = ArrayOrObject.Object(DataModelStruct().add(field("message", "hi")))

        // act
        connection.notify("tell", params)
        let note = transport.nextWritten().getNotificationBodyOrThrow()

        // assert
        @Expect("tell", note.method)
        @Expect("hi", fieldOf(note.params, "message").asStringOrThrow())
    }

    @TestCase
    func paramsThatSerializeToNullAreLeftOut() {
        // arrange
        let transport = FakeTransport()
        let connection = Connection(transport, FakeHandler(), getGlobalLogger())

        // act
        connection.notify("tell", Nullable<Int32>.Null)
        let note = transport.nextWritten().getNotificationBodyOrThrow()

        // assert
        @Assert(note.params.isNone())
    }

    @TestCase
    func paramsThatAreNeitherArrayNorObjectAreRefused() {
        // arrange
        let transport = FakeTransport()
        let connection = Connection(transport, FakeHandler(), getGlobalLogger())

        // act
        let e = @AssertThrows[RpcException](connection.notify("tell", 42i32))

        // assert
        @Expect(ErrorCode.INVALID_PARAMS, e.code)
    }
}

@Test
class ConnectionCloseTest {
    @TestCase
    func closeEndsAServeLoopBlockedOnARead() {
        // arrange
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
        // arrange
        let (connection, transport) = serving(FakeHandler())
        let pending = connection.request<ArrayOrObject, Int64>("ask", emptyParams())
        transport.nextWritten()

        // act
        connection.close()

        // assert
        let e = @AssertThrows[RpcException](pending.await())
        @Expect(ErrorCode.INTERNAL_ERROR, e.code)
    }

    @TestCase
    func aPeerHangUpWakesACallerWaitingForAnAnswer() {
        // arrange
        let (connection, transport) = serving(FakeHandler())
        let pending = connection.request<ArrayOrObject, Int64>("ask", emptyParams())
        transport.nextWritten()

        // act
        transport.hangUp()

        // assert
        let e = @AssertThrows[RpcException](pending.await())
        @Expect(ErrorCode.INTERNAL_ERROR, e.code)
    }

    @TestCase
    func closeTellsInFlightHandlersToGiveUp() {
        // arrange
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

        // act
        connection.close()
        release.add(true)

        // assert
        @Assert(token.isCancelled)
    }

    @TestCase
    func aClosedConnectionIsClosedForGoodAndWritesNothing() {
        // arrange - `serve` unwinding and an explicit close can both land
        let transport = FakeTransport()
        let connection = Connection(transport, FakeHandler(), getGlobalLogger())

        // act
        connection.close()
        connection.close()

        // assert
        @Assert(connection.isClosed())
        @AssertThrows[TransportException](connection.notify("tell", emptyParams()))
    }
}
