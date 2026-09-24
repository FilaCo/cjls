package jsonrpc

import std.collection.ArrayList
import std.io.*
import std.unittest.*
import std.unittest.testmacro.*
import std.unittest.prop_test.*
import stdx.log.*
import stdx.serialization.serialization.*
import stdxx.IntegerOrString
import stdxx.serialization.*

func framed(payload: Array<Byte>): ByteBuffer {
    let bytes = ByteBuffer()
    bytes.write("Content-Length: ${payload.size}\r\n\r\n".toArray())
    bytes.write(payload)
    bytes
}

func framed(payload: String): ByteBuffer {
    framed(payload.toArray())
}

func raw(bytes: String): ByteBuffer {
    let buffer = ByteBuffer()
    buffer.write(bytes.toArray())
    buffer
}

func reading(source: InputStream): FramedJsonRpcTransport {
    FramedJsonRpcTransport(source, ByteBuffer(), getGlobalLogger())
}

/**
 * Hands out at most `chunk` bytes per `read`, the way a pipe does under load; a `ByteBuffer`
 * always fills a read in full.
 */
class ChunkedInputStream <: InputStream {
    private var pos = 0

    ChunkedInputStream(private let data: Array<Byte>, private let chunk: Int64) {}

    public func read(buffer: Array<Byte>): Int64 {
        let count = min(chunk, min(buffer.size, data.size - pos))
        data.copyTo(buffer, pos, 0, count)
        pos += count
        count
    }
}

@Test
class JsonRpcTransportReadTest {
    @TestCase[bytes in [ "", "Content-Length: 33\r\n" ]]
    func theStreamEndingBeforeAFrameReadsAsEof(bytes: String) {
        // act & assert
        @Assert(reading(raw(bytes)).read().isNone())
    }

    @TestCase
    func aReadConsumesExactlyOneFrame() {
        // arrange
        let bytes = raw("")
        bytes.write(readToEnd(framed(##"{"jsonrpc":"2.0","id":1,"method":"first"}"##)))
        bytes.write(readToEnd(framed(##"{"jsonrpc":"2.0","method":"second"}"##)))
        let transport = reading(bytes)

        // act
        let first = transport.read().getOrThrow()
        let second = transport.read().getOrThrow()

        // assert
        @Expect("first", first.getRequestBodyOrThrow().method)
        @Expect("second", second.getNotificationBodyOrThrow().method)
        @Assert(transport.read().isNone())
    }

    @TestCase
    func contentLengthCountsBytesNotChars() {
        // arrange
        let payload = ##"{"jsonrpc":"2.0","method":"m","params":{"text":"привет"}}"##

        // act
        let note = reading(framed(payload)).read().getOrThrow().getNotificationBodyOrThrow()

        // assert
        @Expect("привет", fieldOf(note.params, "text").asStringOrThrow())
    }

    @TestCase
    func aFrameArrivingInShortReadsIsReassembled() {
        // arrange - larger than the buffered stream's own buffer, so a read has to go past it
        let payload = "{\"jsonrpc\":\"2.0\",\"method\":\"m\",\"params\":{\"pad\":\"${"x" * 100000}\"}}"
        let bytes = readToEnd(framed(payload))

        // act
        let note = reading(ChunkedInputStream(bytes, 4096)).read().getOrThrow().getNotificationBodyOrThrow()

        // assert
        @Expect(100000, fieldOf(note.params, "pad").asStringOrThrow().size)
    }

    @TestCase[pair in [
        ("Content-Length: 50\r\n\r\n{\"jsonrpc\":\"2.0\"}", "JSON-RPC content truncated: expected 50 bytes, got 17"),
        ("Content-Length: 33554432\r\n\r\nshort", "JSON-RPC content truncated: expected 33554432 bytes, got 5"),
        ("Content-Length: 33554433\r\n\r\nshort",
            "JSON-RPC body size limit exceeded: expected at most 33554432, got 33554433 bytes"),
        ("Content-Length: nope\r\n\r\n{}", "\"Content-Length\" value is invalid")
    ]]
    func aBrokenFrameLosesTheFraming(pair: (String, String)) {
        // arrange - the limit is checked before anything is allocated, and is inclusive
        let (bytes, message) = pair

        // act
        let e = @AssertThrows[TransportException](reading(raw(bytes)).read())

        // assert
        @Assert(e.message.startsWith(message))
    }
}

@Test
class JsonRpcTransportDecodeErrorTest {
    @TestCase
    func anEmptyFrameIsAParseError() {
        // act
        let e = @AssertThrows[RpcException](reading(raw("Content-Length: 0\r\n\r\n")).read())

        // assert
        @Expect(ErrorCode.PARSE_ERROR, e.code)
    }

    @TestCase[payload in [ "not json".toArray(), "{\"a\":".toArray(), "{,}".toArray(), [0xFFu8, 0xFEu8] ]]
    func contentThatIsNoJsonIsAParseError(payload: Array<Byte>) {
        // act
        let e = @AssertThrows[RpcException](reading(framed(payload)).read())

        // assert
        @Expect(ErrorCode.PARSE_ERROR, e.code)
    }

    @TestCase[payload in [ "[1,2,3]", "42", "\"string\"", "null", ##"{"jsonrpc":"1.0","method":"m"}"## ]]
    func jsonThatIsNoMessageIsAnInvalidRequest(payload: String) {
        // act
        let e = @AssertThrows[RpcException](reading(framed(payload)).read())

        // assert
        @Expect(ErrorCode.INVALID_REQUEST, e.code)
    }

    @TestCase
    func aFrameThatDoesNotDecodeLeavesTheStreamInSync() {
        // arrange
        let bytes = raw("Content-Length: 0\r\n\r\n")
        bytes.write(readToEnd(framed("not json")))
        bytes.write(readToEnd(framed("[1,2,3]")))
        bytes.write(readToEnd(framed(##"{"jsonrpc":"2.0","method":"m"}"##)))
        let transport = reading(bytes)

        // act
        @AssertThrows[RpcException](transport.read())
        @AssertThrows[RpcException](transport.read())
        @AssertThrows[RpcException](transport.read())
        let note = transport.read().getOrThrow().getNotificationBodyOrThrow()

        // assert
        @Expect("m", note.method)
    }
}

@Test
@Configure[randomSeed: 100500]
class JsonRpcTransportWriteTest {
    // the writer is buffered, so an unflushed frame would read back empty
    func written(body: Body): String {
        let out = ByteBuffer()
        FramedJsonRpcTransport(ByteBuffer(), out, getGlobalLogger()).write(body)
        String.fromUtf8(readToEnd(out))
    }

    @TestCase
    func aFrameIsTheHeaderThenTheContent() {
        // act
        let bytes = written(RequestBody(Integer(1), "m").enveloped())

        // assert
        @Expect("Content-Length: 37\r\n\r\n{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"m\"}", bytes)
    }

    @TestCase[method in random()]
    func theDeclaredLengthIsTheContentsSizeInBytes(method: String) {
        // act - once with whatever the generator gives, once with multi-byte chars for certain
        let parts = written(NotificationBody(method).enveloped()).split("\r\n\r\n", 2)
        let cyrillic = written(NotificationBody("${method}привет").enveloped()).split("\r\n\r\n", 2)

        // assert
        @Expect(parts[1].size, Int64(Header.parse(parts[0]).contentLength))
        @Expect(cyrillic[1].size, Int64(Header.parse(cyrillic[0]).contentLength))
    }

    @TestCase
    func framesWrittenInARowReadBackInOrder() {
        // arrange
        let wire = ByteBuffer()
        let sender = FramedJsonRpcTransport(ByteBuffer(), wire, getGlobalLogger())
        let receiver = reading(wire)
        let methods = ["a", "b", "c", "d"]

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

/**
 * A stream that owns something, the way a file or a socket does; a `ByteBuffer` is no
 * `Resource`, so it cannot show whether `close` reached the stream below.
 */
class ClosableStream <: InputStream & OutputStream & Resource {
    var closeCount = 0

    public func read(_: Array<Byte>): Int64 {
        0
    }

    public func write(_: Array<Byte>): Unit {}

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
    func closeReleasesTheStreamsUnderneathOnce() {
        // arrange - shutdown paths overlap, and a stream closed twice may well fault
        let source = ClosableStream()
        let sink = ClosableStream()
        let transport = FramedJsonRpcTransport(source, sink, getGlobalLogger())

        // act
        transport.close()
        transport.close()

        // assert
        @Assert(transport.isClosed())
        @Expect(1, source.closeCount)
        @Expect(1, sink.closeCount)
    }

    @TestCase
    func closeSurvivesStreamsThatOwnNothing() {
        // arrange
        let transport = FramedJsonRpcTransport(ByteBuffer(), ByteBuffer(), getGlobalLogger())

        // act
        transport.close()

        // assert
        @Assert(transport.isClosed())
    }

    @TestCase
    func aClosedTransportReadsAsEofWithAFrameUnread() {
        // arrange
        let transport = reading(framed(##"{"jsonrpc":"2.0","method":"m"}"##))

        // act
        transport.close()

        // assert
        @Assert(transport.read().isNone())
    }

    @TestCase
    func aClosedTransportWritesNothing() {
        // arrange - a half-written frame would desync the peer
        let out = ByteBuffer()
        let transport = FramedJsonRpcTransport(ByteBuffer(), out, getGlobalLogger())

        // act
        transport.close()

        // assert
        @AssertThrows[TransportException](transport.write(NotificationBody("m").enveloped()))
        @Expect(0, readToEnd(out).size)
    }
}
