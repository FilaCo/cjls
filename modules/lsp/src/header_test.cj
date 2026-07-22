package lsp

import std.io.{ByteBuffer, BufferedInputStream}
import std.unittest.prop_test.*

@Test
class HeaderParseStringTest {
    @TestCase[pair in [
        ("Content-Length: 42\r\n", 42),
        ("Content-Length: 0\r\n", 0),
        ("Content-Length: 1\r\n", 1),
        ("Content-Length: 999999999\r\n", 999999999)
    ]]
    func parseContentLengthOnly(pair: (String, Int64)) {
        // arrange
        let (input, expectedLength) = pair
        let expectedContentType = Header.CONTENT_TYPE_DEFAULT

        // act
        let header = Header.parse(input)

        // assert
        @Expect(expectedLength, header.contentLength)
        @Expect(expectedContentType, header.contentType)
    }

    @TestCase
    func parseContentLengthAndType() {
        // arrange
        let input = "Content-Length: 42\r\nContent-Type: application/vscode-jsonrpc; charset=utf-8\r\n"

        // act
        let header = Header.parse(input)

        // assert
        @Expect(42, header.contentLength)
        @Expect("application/vscode-jsonrpc; charset=utf-8", header.contentType)
    }

    @TestCase[unknownField in [
        "X-Custom: whatever",
        "Trace-Id: abc-123",
        "Authorization: Bearer token"
    ]]
    func parseUnknownFieldIsIgnored(unknownField: String) {
        // arrange
        let input = "Content-Length: 7\r\n${unknownField}\r\n"
        let expectedContentType = Header.CONTENT_TYPE_DEFAULT

        // act
        let header = Header.parse(input)

        // assert
        @Expect(7, header.contentLength)
        @Expect("application/vscode-jsonrpc; charset=utf-8", header.contentType)
    }

    @TestCase
    func parseFieldWithoutSeparatorIsSkipped() {
        // arrange
        let input = "Content-Length: 7\r\nGarbageField\r\n"

        // act
        let header = Header.parse(input)

        // assert
        @Expect(7, header.contentLength)
    }

    @TestCase
    func parseMissingContentLengthThrows() {
        // arrange
        let input = "Content-Type: application/vscode-jsonrpc; charset=utf-8\r\n"

        // act
        let e = @AssertThrows[HeaderContentLengthMissingException](Header.parse(input))

        // assert
        @Expect("Required field \"Content-Length\" is missing", e.message)
    }

    @TestCase[negativeValue in ["-1", "-5", "-999"]]
    func parseNegativeContentLengthThrows(negativeValue: String) {
        // arrange
        let input = "Content-Length: ${negativeValue}\r\n"

        // act
        let e = @AssertThrows[HeaderContentLengthNegativeException](Header.parse(input))

        // assert
        @Expect("\"Content-Length\" must be non-negative", e.message)
    }

    @TestCase[garbageValue in ["abc", "", "3.14", "true"]]
    func parseNonNumericContentLengthThrows(garbageValue: String) {
        // arrange
        let input = "Content-Length: ${garbageValue}\r\n"

        // act & assert
        let e = @AssertThrows[HeaderContentLengthInvalidException](Header.parse(input))
    }

    @TestCase
    func parseEmptyHeaderBlockThrowsMissing() {
        // arrange
        let input = "\r\n\r\n"

        // act
        let e = @AssertThrows[HeaderContentLengthMissingException](Header.parse(input))

        // assert
        @Expect("Required field \"Content-Length\" is missing", e.message)
    }

    @TestCase
    func tryParseReturnsNoneOnFailure() {
        // arrange
        let input = "Content-Length: not-a-number\r\n"

        // act
        let result = Header.tryParse(input)

        // assert
        @Assert(result.isNone())
    }

    @TestCase
    func tryParseReturnsHeaderOnSuccess() {
        // arrange
        let input = "Content-Length: 100\r\n"

        // act
        let result = Header.tryParse(input)

        // assert
        @Assert(result.isSome())
        @Expect(100, result.getOrThrow().contentLength)
    }
}

@Test
class HeaderParseStreamTest {
    @Frozen
    func makeInput(bytes: Array<Byte>): BufferedInputStream<ByteBuffer>{
        let bb = ByteBuffer()
        bb.write(bytes)
        BufferedInputStream(bb)
    }

    @TestCase
    func parseSimpleHeaderFromStream() {
        // arrange
        let raw = "Content-Length: 42\r\n\r\n".toArray()
        let input = makeInput(raw)

        // act
        let header = Header.parse(input)

        // assert
        @Assert(header.isSome())
        @Expect(42, header.getOrThrow().contentLength)
    }

    @TestCase
    func parseHeaderWithContentTypeFromStream() {
        // arrange
        let raw = "Content-Length: 7\r\nContent-Type: application/xml; charset=utf-16\r\n\r\n".toArray()
        let input = makeInput(raw)

        // act
        let header = Header.parse(input)

        // assert
        @Assert(header.isSome())
        let h = header.getOrThrow()
        @Expect(7, h.contentLength)
        @Expect("application/xml; charset=utf-16", h.contentType)
    }

    @TestCase
    func parseHeaderWithUnknownFieldFromStream() {
        // arrange
        let raw = "Content-Length: 7\r\nX-Custom: foo\r\n\r\n".toArray()
        let input = makeInput(raw)

        // act
        let header = Header.parse(input)

        // assert
        @Assert(header.isSome())
        @Expect(7, header.getOrThrow().contentLength)
    }

    @TestCase
    func parseHeaderDoesNotConsumeBody() {
        // arrange
        let raw = "Content-Length: 5\r\n\r\nhello".toArray()
        let input = makeInput(raw)

        // act
        let header = Header.parse(input)

        // assert - header parsed, body untouched
        @Assert(header.isSome())
        @Expect(5, header.getOrThrow().contentLength)
        @Expect(Some(b'h'), input.readByte())
    }

    @TestCase
    func parseReturnsNoneOnEofBeforeTerminator() {
        // arrange
        let raw = "Content-Length: 5\r\n".toArray()
        let input = makeInput(raw)

        // act
        let header = Header.parse(input)

        // assert
        @Assert(header.isNone())
    }

    @TestCase
    func parseReturnsNoneOnEmptyStream() {
        // arrange
        let input = makeInput(Array<Byte>())

        // act
        let header = Header.parse(input)

        // assert
        @Assert(header.isNone())
    }

    @TestCase
    func parseMultipleHeadersSequentially() {
        // arrange - two pipelined messages in one stream
        let raw = "Content-Length: 3\r\n\r\nabcContent-Length: 4\r\n\r\nwxyz".toArray()
        let input = makeInput(raw)

        // act - first message header
        let h1 = Header.parse(input)

        // assert - first header
        @Assert(h1.isSome())
        @Expect(3, h1.getOrThrow().contentLength)

        // act - skip 3 body bytes "abc"
        var body = Array<Byte>(3, repeat: 0)
        input.read(body)

        // act - second message header
        let h2 = Header.parse(input)

        // assert - second header
        @Assert(h2.isSome())
        @Expect(4, h2.getOrThrow().contentLength)
    }
}

@Test
@Configure[randomSeed: 100500]
class HeaderPropertyTest {
    @TestCase[n in random()]
    func streamParseMatchesStrParse(n: Int64) {
        // Property: parsing a header from a BufferedInputStream<ByteBuffer>
        // yields the same result as parsing the equivalent string. Only
        // non-negative content-lengths produce well-formed headers.

        // arrange
        if (n < 0) {
            return
        }
        let headerStr = "Content-Length: ${n}\r\n\r\n"
        let fromStr = Header.parse(headerStr)
        let bb = ByteBuffer()
        bb.write(headerStr.toArray())

        // act
        let fromStream = Header.parse(BufferedInputStream(bb))

        // assert
        @Assert(fromStream.isSome())
        @Expect(fromStr.contentLength, fromStream.getOrThrow().contentLength)
    }
}
