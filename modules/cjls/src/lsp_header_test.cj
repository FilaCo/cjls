package cjls

import std.io.{ByteBuffer, BufferedInputStream}
import std.unittest.prop_test.*

@Test
class LSPHeaderParseStringTest {
    @TestCase[pair in [
        ("Content-Length: 42\r\n", Int64(42)),
        ("Content-Length: 0\r\n", Int64(0)),
        ("Content-Length: 1\r\n", Int64(1)),
        ("Content-Length: 999999999999\r\n", Int64(999999999999))
    ]]
    func parseContentLengthOnly(pair: (String, Int64)) {
        // arrange
        let (input, expectedLength) = pair
        let expectedContentType = LSPHeader.CONTENT_TYPE_DEFAULT

        // act
        let header = LSPHeader.parse(input)

        // assert
        @Expect(expectedLength, header.contentLength)
        @PowerAssert(expectedContentType, header.contentType)
    }

    @TestCase
    func parseContentLengthAndType() {
        // arrange
        let input = "Content-Length: 42\r\nContent-Type: application/vscode-jsonrpc; charset=utf-8\r\n"

        // act
        let header = LSPHeader.parse(input)

        // assert
        @Expect(42, header.contentLength)
        @PowerAssert("application/vscode-jsonrpc; charset=utf-8", header.contentType)
    }

    @TestCase[unknownField in [
        "X-Custom: whatever",
        "Trace-Id: abc-123",
        "Authorization: Bearer token"
    ]]
    func parseUnknownFieldIsIgnored(unknownField: String) {
        // arrange
        let input = "Content-Length: 7\r\n${unknownField}\r\n"
        let expectedContentType = LSPHeader.CONTENT_TYPE_DEFAULT

        // act
        let header = LSPHeader.parse(input)

        // assert
        @Expect(7, header.contentLength)
        @PowerAssert(expectedContentType, header.contentType)
    }

    @TestCase
    func parseFieldWithoutSeparatorIsSkipped() {
        // arrange
        let input = "Content-Length: 7\r\nGarbageField\r\n"

        // act
        let header = LSPHeader.parse(input)

        // assert
        @PowerAssert(7, header.contentLength)
    }

    @TestCase
    func parseMissingContentLengthThrows() {
        // arrange
        let input = "Content-Type: application/vscode-jsonrpc; charset=utf-8\r\n"

        // act
        let e = @AssertThrows[LSPHeaderContentLengthMissingException](LSPHeader.parse(input))

        // assert
        @PowerAssert("Required field \"Content-Length\" is missing", e.message)
    }

    @TestCase[negativeValue in ["-1", "-5", "-999"]]
    func parseNegativeContentLengthThrows(negativeValue: String) {
        // arrange
        let input = "Content-Length: ${negativeValue}\r\n"

        // act
        let e = @AssertThrows[LSPHeaderContentLengthNegativeException](LSPHeader.parse(input))

        // assert
        @PowerAssert("\"Content-Length\" must be non-negative", e.message)
    }

    @TestCase[garbageValue in ["abc", "", "3.14", "true"]]
    func parseNonNumericContentLengthThrows(garbageValue: String) {
        // arrange
        let input = "Content-Length: ${garbageValue}\r\n"

        // act & assert
        let e = @AssertThrows[LSPHeaderContentLengthInvalidException](LSPHeader.parse(input))
    }

    @TestCase
    func parseEmptyHeaderBlockThrowsMissing() {
        // arrange
        let input = "\r\n\r\n"

        // act
        let e = @AssertThrows[LSPHeaderContentLengthMissingException](LSPHeader.parse(input))

        // assert
        @PowerAssert("Required field \"Content-Length\" is missing", e.message)
    }

    @TestCase
    func tryParseReturnsNoneOnFailure() {
        // arrange
        let input = "Content-Length: not-a-number\r\n"

        // act
        let result = LSPHeader.tryParse(input)

        // assert
        @Assert(result.isNone())
    }

    @TestCase
    func tryParseReturnsHeaderOnSuccess() {
        // arrange
        let input = "Content-Length: 100\r\n"

        // act
        let result = LSPHeader.tryParse(input)

        // assert
        @Assert(result.isSome())
        @PowerAssert(100, result.getOrThrow().contentLength)
    }

    @TestCase
    func toStringRoundTrips() {
        // arrange
        let header = LSPHeader(42)

        // act
        let str = header.toString()

        // assert
        @PowerAssert("Content-Length: 42\r\nContent-Type: application/vscode-jsonrpc; charset=utf-8\r\n", str)
    }

    @TestCase
    func toStringWithCustomContentType() {
        // arrange
        let header = LSPHeader(42, contentType: "application/json; charset=cp-1251")

        // act
        let str = header.toString()

        // assert
        @PowerAssert("Content-Length: 42\r\nContent-Type: application/json; charset=cp-1251\r\n", str)
    }
}

@Test
class LSPHeaderParseStreamTest {
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
        let header = LSPHeader.parse(input)

        // assert
        @Assert(header.isSome())
        @PowerAssert(42, header.getOrThrow().contentLength)
    }

    @TestCase
    func parseHeaderWithContentTypeFromStream() {
        // arrange
        let raw = "Content-Length: 7\r\nContent-Type: application/xml; charset=utf-16\r\n\r\n".toArray()
        let input = makeInput(raw)

        // act
        let header = LSPHeader.parse(input)

        // assert
        @Assert(header.isSome())
        let h = header.getOrThrow()
        @Expect(7, h.contentLength)
        @PowerAssert("application/xml; charset=utf-16", h.contentType)
    }

    @TestCase
    func parseHeaderWithUnknownFieldFromStream() {
        // arrange
        let raw = "Content-Length: 7\r\nX-Custom: foo\r\n\r\n".toArray()
        let input = makeInput(raw)

        // act
        let header = LSPHeader.parse(input)

        // assert
        @Assert(header.isSome())
        @PowerAssert(7, header.getOrThrow().contentLength)
    }

    @TestCase
    func parseHeaderDoesNotConsumeBody() {
        // arrange
        let raw = "Content-Length: 5\r\n\r\nhello".toArray()
        let input = makeInput(raw)

        // act
        let header = LSPHeader.parse(input)

        // assert - header parsed, body untouched
        @Assert(header.isSome())
        @PowerAssert(5, header.getOrThrow().contentLength)
        @PowerAssert(Some(b'h'), input.readByte())
    }

    @TestCase
    func parseReturnsNoneOnEofBeforeTerminator() {
        // arrange
        let raw = "Content-Length: 5\r\n".toArray()
        let input = makeInput(raw)

        // act
        let header = LSPHeader.parse(input)

        // assert
        @Assert(header.isNone())
    }

    @TestCase
    func parseReturnsNoneOnEmptyStream() {
        // arrange
        let input = makeInput(Array<Byte>())

        // act
        let header = LSPHeader.parse(input)

        // assert
        @Assert(header.isNone())
    }

    @TestCase
    func parseMultipleHeadersSequentially() {
        // arrange - two pipelined messages in one stream
        let raw = "Content-Length: 3\r\n\r\nabcContent-Length: 4\r\n\r\nwxyz".toArray()
        let input = makeInput(raw)

        // act - first message header
        let h1 = LSPHeader.parse(input)

        // assert - first header
        @Assert(h1.isSome())
        @Expect(3, h1.getOrThrow().contentLength)

        // act - skip 3 body bytes "abc"
        var body = Array<Byte>(3, repeat: 0)
        input.read(body)

        // act - second message header
        let h2 = LSPHeader.parse(input)

        // assert - second header
        @Assert(h2.isSome())
        @PowerAssert(4, h2.getOrThrow().contentLength)
    }
}

@Test
@Configure[randomSeed: 42]
class LSPHeaderPropertyTest {
    @TestCase[n in random()]
    func parseRoundTripsContentLength(n: Int64) {
        // Property: for any non-negative Int64 n, LSPHeader(n).toString()
        // parses back to a header with the same contentLength. Negative n
        // is rejected by parse(), so we skip it (the invariant is only defined
        // on the valid domain).

        // arrange
        if (n < 0) {
            return
        }
        let header = LSPHeader(n)
        let str = header.toString()

        // act
        let parsed = LSPHeader.parse(str)

        // assert
        @PowerAssert(n, parsed.contentLength)
    }

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
        let fromStr = LSPHeader.parse(headerStr)
        let bb = ByteBuffer()
        bb.write(headerStr.toArray())

        // act
        let fromStream = LSPHeader.parse(BufferedInputStream(bb))

        // assert
        @Assert(fromStream.isSome())
        @PowerAssert(fromStr.contentLength, fromStream.getOrThrow().contentLength)
    }
}
