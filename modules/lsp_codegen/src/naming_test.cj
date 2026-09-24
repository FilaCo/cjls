package lsp_codegen

import std.unittest.*
import std.unittest.testmacro.*

@Test
class NamingTest {
    @TestCase[pair in [("ParseError", "PARSE_ERROR"), ("LSPErrorCodes", "LSP_ERROR_CODES"), ("URI", "URI"),
        ("serverCancelled", "SERVER_CANCELLED")]]
    func upperSnakeCaseSplitsAtEveryWordAndKeepsAcronymsWhole(pair: (String, String)) {
        // arrange
        let (name, expected) = pair

        // act & assert
        @Expect(expected, name.toAsciiUpperSnakeCase())
    }

    @TestCase[pair in [("TextDocumentSyncKind", "text_document_sync_kind"), ("URIParser", "uri_parser"),
        ("_InitializeParams", "__initialize_params")]]
    func lowerSnakeCaseNamesAFileAfterItsDeclaration(pair: (String, String)) {
        // arrange
        let (name, expected) = pair

        // act & assert
        @Expect(expected, name.toAsciiLowerSnakeCase())
    }

    @TestCase[pair in [("markdown", "Markdown"), ("PlainText", "PlainText")]]
    func pascalCaseCapitalisesEachWord(pair: (String, String)) {
        // arrange
        let (name, expected) = pair

        // act & assert
        @Expect(expected, name.toAsciiPascalCase())
    }

    @TestCase[pair in [("Location", "Locations"), ("Box", "Boxes"), ("Entry", "Entries"), ("Key", "Keys")]]
    func pluralOfFollowsTheRegularEnglishEndings(pair: (String, String)) {
        // arrange
        let (name, expected) = pair

        // act & assert
        @Expect(expected, pluralOf(name))
    }

    @TestCase[pair in [("type", "`type`"), ("Int32", "`Int32`"), ("kind", "kind")]]
    func aReservedIdentifierIsBackquoted(pair: (String, String)) {
        // arrange
        let (name, expected) = pair

        // act & assert
        @Expect(expected, escapedIdent(name).value)
    }
}
