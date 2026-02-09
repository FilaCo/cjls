package lsp.base_proto

import std.unittest.* // cjlint-ignore !G.PKG.01
import std.unittest.testmacro.* // cjlint-ignore !G.PKG.01
import std.io.{StringReader, ByteBuffer}

@Test
class LspHeaderTest {
    @TestCase[pairs in [ 
("Content-Length: 123\r\nContent-Type: application/vscode; charset=utf8\r\n", LspHeader(contentLength: 123, contentType: Some("application/vscode; charset=utf8"))), 
("Content-Length: 123\r\n\r\n", LspHeader(contentLength: 123)), 
("Content-Length: 123\r\n\r\n", LspHeader(contentLength: 123, contentType: Some("application/vscode-jsonrpc; charset=utf-8"))), 
("Content-Length: 123\r\nContent-Type: application/vscode-jsonrpc; charset=utf-8\r\n", LspHeader(contentLength: 123)), 
("Content-Length: 123\r\nContent-Type: application/vscode-jsonrpc; charset=utf-8\r\n", LspHeader(contentLength: 123, contentType: Some("application/vscode-jsonrpc; charset=utf-8"))), 
("Content-Length: 123\r\nContent-Type: application/vscode-jsonrpc\nwtf; charset=utf-8\r\n", LspHeader(contentLength: 123, contentType: Some("application/vscode-jsonrpc\nwtf; charset=utf-8"))), 
 ] 
]
    func smoke(pairs: (String, LspHeader)) {
        // arrange
        let (input, expected) = pairs

        // act
        let actual = LspHeader.read(getReader(input))

        // assert
        @PowerAssert(expected.contentLength == actual.contentLength)
        @PowerAssert(expected.contentType == expected.contentType)
    }

    @TestCase
    func invalidFieldsCount() {
        // arrange
        let input = getReader("\r\n")

        // act
        // assert
        @AssertThrows[LspRequestHeaderInvalidFieldsCountException](LspHeader.read(input))
    }

    @TestCase
    func invalidFieldFormat() {
        // arrange
        let input = getReader("Content-type=whatever\r\n\r\n")

        // act
        // assert
        @AssertThrows[LspRequestHeaderInvalidFieldFormatException](LspHeader.read(input))
    }

    @TestCase
    func unknownFieldName() {
        // arrange
        let input = getReader("Content-Whatever: why\r\n\r\n")

        // act
        // assert
        @AssertThrows[LspRequestHeaderUnknownFieldNameException<Array<String>>](LspHeader.read(input))
    }

    static func getReader(input: String): StringReader<ByteBuffer> {
        StringReader(ByteBuffer(input.toArray()))
    }
}
