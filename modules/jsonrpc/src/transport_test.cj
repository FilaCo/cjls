package jsonrpc

import std.collection.ArrayList
import std.io.*
import std.unittest.*
import std.unittest.testmacro.*
import std.unittest.prop_test.*
import stdx.log.*
import stdx.serialization.serialization.*
import stdxx.*

func framed(payload: String): ByteBuffer {
    let bb = ByteBuffer()
    bb.write("Content-Length: ${payload.toArray().size}\r\n\r\n".toArray())
    bb.write(payload.toArray())
    bb
}

func reading(source: ByteBuffer): FramedJsonRpcTransport {
    FramedJsonRpcTransport(source, ByteBuffer(), getGlobalLogger())
}

/**
 * Hands out at most `chunk` bytes per `read`, the way a pipe or a socket does
 * under load. A `ByteBuffer` always satisfies a read in full, so it can never
 * drive `readExactly`'s byte-at-a-time top-up loop.
 */
class ChunkedInputStream <: InputStream {
    private var pos = 0

    ChunkedInputStream(private let data: Array<Byte>, private let chunk: Int64) {}

    public func read(buffer: Array<Byte>): Int64 {
        if (pos >= data.size || buffer.size == 0) {
            return 0
        }
        var count = data.size - pos
        if (count > chunk) {
            count = chunk
        }
        if (count > buffer.size) {
            count = buffer.size
        }
        data.copyTo(buffer, pos, 0, count)
        pos += count
        count
    }
}

@Test
class JsonRpcTransportReadTest {
    @TestCase
    func readRequest() {
        // arrange
        let transport = reading(framed("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\"}"))

        // act
        let req = transport.read().getOrThrow().getRequestBodyOrThrow()

        // assert
        @Expect(Integer(1), req.id)
        @Expect("initialize", req.method)
        @Assert(req.params.isNone())
    }

    @TestCase
    func readNotification() {
        // arrange
        let transport = reading(framed("{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}"))

        // act
        let note = transport.read().getOrThrow().getNotificationBodyOrThrow()

        // assert
        @Expect("exit", note.method)
        @Assert(note.params.isNone())
    }

    @TestCase
    func readResponse() {
        // arrange
        let transport = reading(framed("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":42}"))

        // act
        let resp = transport.read().getOrThrow().getResponseBodyOrThrow()

        // assert
        @Expect(Integer(1), resp.id.getOrThrow())
        @Expect(42, intOf(resp.resultOrError.getResultOrThrow()))
    }

    @TestCase
    func readIgnoresExtraHeaderFields() {
        // arrange
        let payload = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}"
        let bb = ByteBuffer()
        bb.write(
            "Content-Length: ${payload.toArray().size}\r\nContent-Type: application/vscode-jsonrpc; charset=utf-8\r\nX-Custom: 1\r\n\r\n"
                .toArray())
        bb.write(payload.toArray())

        // act
        let note = reading(bb).read().getOrThrow().getNotificationBodyOrThrow()

        // assert
        @Expect("exit", note.method)
    }

    @TestCase
    func readReturnsNoneOnCleanEof() {
        // arrange
        let transport = reading(ByteBuffer())

        // act
        let body = transport.read()

        // assert
        @Assert(body.isNone())
    }

    @TestCase
    func readReturnsNoneOnHeaderTruncatedMidStream() {
        // arrange - peer died before the "\r\n\r\n" terminator. `Header.parse`
        // cannot tell this apart from a clean EOF, so it surfaces as one.
        let bb = ByteBuffer()
        bb.write("Content-Length: 33\r\n".toArray())

        // act
        let body = reading(bb).read()

        // assert
        @Assert(body.isNone())
    }

    @TestCase
    func readConsumesExactlyContentLength() {
        // arrange - two pipelined frames back to back; the first read must not
        // eat into the second frame's header.
        let first = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\"}"
        let second = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}"
        let bb = ByteBuffer()
        bb.write("Content-Length: ${first.toArray().size}\r\n\r\n${first}".toArray())
        bb.write("Content-Length: ${second.toArray().size}\r\n\r\n${second}".toArray())
        let transport = reading(bb)

        // act
        let firstBody = transport.read().getOrThrow()
        let secondBody = transport.read().getOrThrow()
        let thirdBody = transport.read()

        // assert
        @Expect("initialize", firstBody.getRequestBodyOrThrow().method)
        @Expect("exit", secondBody.getNotificationBodyOrThrow().method)
        @Assert(thirdBody.isNone())
    }

    @TestCase
    func readCountsContentLengthInBytesNotChars() {
        // arrange - a multi-byte UTF-8 payload: `Content-Length` is a byte count,
        // so a char-based read would truncate the frame.
        let payload = "{\"jsonrpc\":\"2.0\",\"method\":\"m\",\"params\":{\"text\":\"привет\"}}"
        let transport = reading(framed(payload))

        // act
        let note = transport.read().getOrThrow().getNotificationBodyOrThrow()

        // assert
        @Assert(payload.toArray().size > payload.runes().count())
        @Expect("привет", strOf(fieldOf(note.params, "text")))
    }

    @TestCase
    func readTruncatedPayloadThrows() {
        // arrange - header promises 50 bytes, stream holds 17
        let bb = ByteBuffer()
        bb.write("Content-Length: 50\r\n\r\n{\"jsonrpc\":\"2.0\"}".toArray())

        // act
        let e = @AssertThrows[TransportException](reading(bb).read())

        // assert
        @Expect("JSON-RPC content truncated: expected 50 bytes, got 17", e.message)
    }

    @TestCase
    func readReassemblesPayloadDeliveredInShortReads() {
        // arrange - a socket-like peer that dribbles the frame out a few bytes at
        // a time, rather than the all-at-once `ByteBuffer` every other case uses.
        let payload = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}"
        let raw = "Content-Length: ${payload.toArray().size}\r\n\r\n${payload}".toArray()
        let transport = FramedJsonRpcTransport(ChunkedInputStream(raw, 4), ByteBuffer(), getGlobalLogger())

        // act
        let note = transport.read().getOrThrow().getNotificationBodyOrThrow()

        // assert
        @Expect("exit", note.method)
    }

    @TestCase
    func readMalformedHeaderThrows() {
        // arrange
        let bb = ByteBuffer()
        bb.write("Content-Length: nope\r\n\r\n{}".toArray())

        // act & assert
        @AssertThrows[TransportException](reading(bb).read())
    }

    @TestCase
    func readRejectsFrameOverSizeLimit() {
        // arrange - one byte over the 32 MiB cap; the guard must fire before the
        // array is allocated, so the stream itself stays tiny.
        let bb = ByteBuffer()
        bb.write("Content-Length: 33554433\r\n\r\nshort".toArray())

        // act & assert
        let e = @AssertThrows[TransportException](reading(bb).read())
    }

    @TestCase
    func readAcceptsFrameAtSizeLimit() {
        // arrange - exactly at the cap: rejected as truncated, not as oversized,
        // which proves the boundary is inclusive.
        let bb = ByteBuffer()
        bb.write("Content-Length: 33554432\r\n\r\nshort".toArray())

        // act
        let e = @AssertThrows[TransportException](reading(bb).read())

        // assert
        @Expect("JSON-RPC content truncated: expected 33554432 bytes, got 5", e.message)
    }
}

@Test
class JsonRpcTransportDecodeErrorTest {
    @TestCase
    func readEmptyPayloadThrowsParseError() {
        // arrange - a well-framed but contentless frame; `InputStream.read` also
        // rejects an empty buffer, so this must be caught before `readExactly`.
        let bb = ByteBuffer()
        bb.write("Content-Length: 0\r\n\r\n".toArray())

        // act
        let e = @AssertThrows[RpcException](reading(bb).read())

        // assert
        @Expect(ErrorCode.PARSE_ERROR, e.code)
        @Expect("JSON-RPC frame declares an empty content", e.message)
    }

    @TestCase[payload in [ "not json at all", "{\"unterminated\":", "{,}", "{\"a\":}" ]]
    func readInvalidJsonThrowsParseError(payload: String) {
        // arrange
        let transport = reading(framed(payload))

        // act
        let e = @AssertThrows[RpcException](transport.read())

        // assert
        @Expect(ErrorCode.PARSE_ERROR, e.code)
        @Assert(e.message.contains("not valid JSON"))
    }

    @TestCase
    func readInvalidUtf8ThrowsParseError() {
        // arrange - 0xFF/0xFE are never valid UTF-8 lead bytes
        let bb = ByteBuffer()
        bb.write("Content-Length: 2\r\n\r\n".toArray())
        bb.write([0xFFu8, 0xFEu8])

        // act
        let e = @AssertThrows[RpcException](reading(bb).read())

        // assert
        @Expect(ErrorCode.PARSE_ERROR, e.code)
        @Assert(e.message.contains("not valid JSON"))
    }

    @TestCase[payload in [ 
 "[1,2,3]", 
 "42", 
 "\"just a string\"", 
 "null", 
 "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":1,\"error\":{\"code\":-1,\"message\":\"x\"}}" 
 ]]
    func readWellFormedJsonThatIsNotAMessageThrowsInvalidRequest(payload: String) {
        // arrange - parses as JSON, but is not a JSON-RPC message
        let transport = reading(framed(payload))

        // act
        let e = @AssertThrows[RpcException](transport.read())

        // assert
        @Expect(ErrorCode.INVALID_REQUEST, e.code)
    }

    @TestCase[payload in [ 
 "{\"method\":\"exit\"}", 
 "{\"jsonrpc\":\"1.0\",\"method\":\"exit\"}", 
 "{\"jsonrpc\":2.0,\"method\":\"exit\"}", 
 "{\"jsonrpc\":null,\"method\":\"exit\"}", 
 "{\"jsonrpc\":\"2.0.0\",\"id\":1,\"method\":\"initialize\"}" 
 ]]
    func readRejectsWrongProtocolVersion(payload: String) {
        // arrange - missing, wrong, mistyped and null "jsonrpc" all violate the
        // same invariant and must be reported identically.
        let transport = reading(framed(payload))

        // act
        let e = @AssertThrows[RpcException](transport.read())

        // assert
        @Expect(ErrorCode.INVALID_REQUEST, e.code)
        @Expect("invalid \"jsonrpc\" field value", e.message)
    }

    @TestCase
    func decodeErrorLeavesStreamInSync() {
        // arrange - the point of separating `RpcException` from
        // `TransportException`: framing survived, so the next frame is readable.
        let bad = "not json"
        let good = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}"
        let bb = ByteBuffer()
        bb.write("Content-Length: 0\r\n\r\n".toArray())
        bb.write("Content-Length: ${bad.toArray().size}\r\n\r\n${bad}".toArray())
        bb.write("Content-Length: 7\r\n\r\n[1,2,3]".toArray())
        bb.write("Content-Length: ${good.toArray().size}\r\n\r\n${good}".toArray())
        let transport = reading(bb)

        // act - three bad frames, each recoverable
        @AssertThrows[RpcException](transport.read())
        @AssertThrows[RpcException](transport.read())
        @AssertThrows[RpcException](transport.read())
        let note = transport.read().getOrThrow().getNotificationBodyOrThrow()

        // assert - the fourth frame still decodes
        @Expect("exit", note.method)
    }

    @TestCase
    func decodeErrorConvertsToResponseError() {
        // arrange
        let transport = reading(framed("not json"))

        // act
        let e = @AssertThrows[RpcException](transport.read())
        let responseError = e.responseError

        // assert - what the caller would put on the wire
        @Expect(ErrorCode.PARSE_ERROR, responseError.code)
        @Expect(e.message, responseError.message)
        @Assert(responseError.data.isNone())
    }
}

@Test
class JsonRpcTransportWriteTest {
    // The writer is buffered, so every exact-bytes assertion below doubles as a
    // flush assertion: an unflushed frame reads back as an empty buffer.
    func writtenBytes(body: Body): String {
        let out = ByteBuffer()
        FramedJsonRpcTransport(ByteBuffer(), out, getGlobalLogger()).write(body)
        String.fromUtf8(readToEnd(out))
    }

    @TestCase
    func writeRequestFraming() {
        // arrange
        let body = RequestBody(Integer(1), "initialize").enveloped()

        // act
        let raw = writtenBytes(body)

        // assert
        @Expect("Content-Length: 46\r\n\r\n{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\"}", raw)
    }

    @TestCase
    func writeNotificationFraming() {
        // arrange
        let body = NotificationBody("exit").enveloped()

        // act
        let raw = writtenBytes(body)

        // assert
        @Expect("Content-Length: 33\r\n\r\n{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}", raw)
    }

    @TestCase
    func writeResponseFraming() {
        // arrange
        let body = ResponseBody.result(Value(Integer(1)), DataModelInt(42)).enveloped()

        // act
        let raw = writtenBytes(body)

        // assert
        @Expect("Content-Length: 36\r\n\r\n{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":42}", raw)
    }

    @TestCase
    func writeDeclaresByteLengthNotCharLength() {
        // arrange - multi-byte payload: the declared length must match the
        // number of bytes on the wire, otherwise the peer desyncs.
        let params = ArrayOrObject.Object(DataModelStruct().add(field("text", "привет")))
        let body = NotificationBody("m", params: params).enveloped()

        // act
        let parts = writtenBytes(body).split("\r\n\r\n", 2)

        // assert
        @Expect(2, parts.size)
        @Expect(parts[1].toArray().size, Int64(Header.parse(parts[0]).contentLength))
        @Assert(parts[1].toArray().size > parts[1].runes().count())
    }

    @TestCase
    func writeMultipleFramesArePipelined() {
        // arrange
        let out = ByteBuffer()
        let transport = FramedJsonRpcTransport(ByteBuffer(), out, getGlobalLogger())

        // act
        transport.write(NotificationBody("initialized").enveloped())
        transport.write(NotificationBody("exit").enveloped())

        // assert
        @Expect(
            "Content-Length: 40\r\n\r\n{\"jsonrpc\":\"2.0\",\"method\":\"initialized\"}Content-Length: 33\r\n\r\n{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}",
            String.fromUtf8(readToEnd(out)))
    }
}

@Test
class JsonRpcTransportRoundTripTest {
    // one ByteBuffer acting as the wire between two peers
    func wired(): (JsonRpcTransport, JsonRpcTransport) {
        let wire = ByteBuffer()
        (FramedJsonRpcTransport(ByteBuffer(), wire, getGlobalLogger()), FramedJsonRpcTransport(wire, ByteBuffer(), getGlobalLogger()))
    }

    @TestCase
    func roundTripManyFramesInOrder() {
        // arrange
        let (sender, receiver) = wired()
        let methods = ["initialize", "initialized", "textDocument/didOpen", "shutdown", "exit"]

        // act
        for (m in methods) {
            sender.write(NotificationBody(m).enveloped())
        }
        let received = ArrayList<String>()
        while (let Some(body) <- receiver.read()) {
            received.add(body.getNotificationBodyOrThrow().method)
        }

        // assert
        @Expect(methods, received.toArray())
    }
}

@Test
@Configure[randomSeed: 100500]
class JsonRpcTransportPropertyTest {
    @TestCase[id in random()]
    func requestIdSurvivesRoundTrip(id: Int32) {
        // Property: any request id written by one peer is read back unchanged.

        // arrange
        let wire = ByteBuffer()
        let sender = FramedJsonRpcTransport(ByteBuffer(), wire, getGlobalLogger())
        let receiver = FramedJsonRpcTransport(wire, ByteBuffer(), getGlobalLogger())

        // act
        sender.write(RequestBody(Integer(id), "initialize").enveloped())
        let req = receiver.read().getOrThrow().getRequestBodyOrThrow()

        // assert
        @Expect(id, req.id.getIntegerOrThrow())
    }

    @TestCase[method in random()]
    func declaredLengthAlwaysMatchesPayload(method: String) {
        // Property: the declared `Content-Length` always equals the byte size of
        // the payload that follows it, whatever the method name contains.

        // arrange
        let out = ByteBuffer()

        // act
        FramedJsonRpcTransport(ByteBuffer(), out, getGlobalLogger()).write(NotificationBody(method).enveloped())
        let parts = String.fromUtf8(readToEnd(out)).split("\r\n\r\n", 2)

        // assert
        @Expect(2, parts.size)
        @Expect(parts[1].toArray().size, Int64(Header.parse(parts[0]).contentLength))
    }
}

/**
 * A stream that owns something, the way a file or a socket does. A `ByteBuffer` is
 * no `Resource`, so it can never show whether `close` reached the stream below.
 */
class ClosableStream <: InputStream & OutputStream & Resource {
    var closeCount = 0

    private let bytes = ByteBuffer()

    public func read(buffer: Array<Byte>): Int64 {
        bytes.read(buffer)
    }

    public func write(buffer: Array<Byte>): Unit {
        bytes.write(buffer)
    }

    public func isClosed(): Bool {
        closeCount > 0
    }

    public func close(): Unit {
        closeCount++
    }
}

@Test
class JsonRpcTransportCloseTest {
    @TestCase
    func closeReleasesTheStreamsUnderneath() {
        // arrange
        let source = ClosableStream()
        let sink = ClosableStream()
        let transport = FramedJsonRpcTransport(source, sink, getGlobalLogger())

        // act
        transport.close()

        // assert
        @Assert(transport.isClosed())
        @Expect(1, source.closeCount)
        @Expect(1, sink.closeCount)
    }

    @TestCase
    func closeIsIdempotent() {
        // arrange - shutdown paths overlap, and a stream closed twice may well fault
        let source = ClosableStream()
        let sink = ClosableStream()
        let transport = FramedJsonRpcTransport(source, sink, getGlobalLogger())

        // act
        transport.close()
        transport.close()

        // assert
        @Expect(1, source.closeCount)
        @Expect(1, sink.closeCount)
    }

    @TestCase
    func closeSurvivesStreamsThatOwnNothing() {
        // arrange - an in-memory stream is not a `Resource`; there is nothing to
        // hand back, and asking for it must not throw
        let transport = FramedJsonRpcTransport(ByteBuffer(), ByteBuffer(), getGlobalLogger())

        // act
        transport.close()

        // assert
        @Assert(transport.isClosed())
    }

    @TestCase
    func aClosedTransportReadsAsEof() {
        // arrange - a frame is sitting there unread: being closed outranks it
        let transport = reading(framed("{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}"))

        // act
        transport.close()

        // assert
        @Assert(transport.read().isNone())
    }

    @TestCase
    func aClosedTransportRefusesToWrite() {
        // arrange - a half-written frame would desync the peer, so the refusal comes
        // before any bytes go out
        let out = ByteBuffer()
        let transport = FramedJsonRpcTransport(ByteBuffer(), out, getGlobalLogger())

        // act
        transport.close()

        // assert
        @AssertThrows[TransportException](transport.write(NotificationBody("exit").enveloped()))
        @Expect(0, readToEnd(out).size)
    }
}
