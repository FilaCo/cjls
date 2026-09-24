package jsonrpc

import std.io.{ByteBuffer, BufferedInputStream}
import std.unittest.*
import std.unittest.testmacro.*
import std.unittest.prop_test.*

@Test
@Configure[randomSeed: 100500]
class HeaderTest {
    @TestCase[length in random()]
    func aContentLengthReadsBackUnlessNegative(length: Int32) {
        // arrange
        let input = "Content-Length: ${length}\r\n"

        // act & assert
        if (length < 0) {
            let e = @AssertThrows[TransportException](Header.parse(input))
            @Expect("\"Content-Length\" must be non-negative", e.message)
        } else {
            @Expect(length, Header.parse(input).contentLength)
        }
    }

    @TestCase[field in [ "Content-Type: application/vscode-jsonrpc; charset=utf-8", "X-Custom: 1", "NoSeparator" ]]
    func anyOtherFieldIsSkipped(field: String) {
        // act
        let after = Header.parse("Content-Length: 7\r\n${field}\r\n")
        let before = Header.parse("${field}\r\nContent-Length: 7\r\n")

        // assert
        @Expect(7, after.contentLength)
        @Expect(7, before.contentLength)
    }

    @TestCase[input in [ "", "\r\n\r\n", "Content-Type: application/vscode-jsonrpc\r\n" ]]
    func aMissingContentLengthIsRefused(input: String) {
        // act
        let e = @AssertThrows[TransportException](Header.parse(input))

        // assert
        @Expect("Required field \"Content-Length\" is missing", e.message)
    }

    @TestCase[value in [ "abc", "", "3.14", "true", "99999999999" ]]
    func aContentLengthThatIsNoInt32IsRefused(value: String) {
        // act & assert
        @AssertThrows[TransportException](Header.parse("Content-Length: ${value}\r\n"))
    }

    @TestCase
    func readingAHeaderLeavesTheContentAfterIt() {
        // arrange
        let bytes = ByteBuffer()
        bytes.write("Content-Length: 5\r\n\r\nhello".toArray())
        let input = BufferedInputStream(bytes)

        // act
        let header = Header.read(input)

        // assert
        @Expect(5, header.getOrThrow().contentLength)
        @Expect(Some(b'h'), input.readByte())
    }
}
