package cjls.handlers

import std.unittest.*
import std.unittest.testmacro.*
import stdxx.Nullable
import cjls.lsp_types.*
import cjls.server.*

func documentSymbols(state: ServerState, uri: String): ?Array<DocumentSymbol> {
    match (handleDocumentSymbol(state.snapshot(), DocumentSymbolParams(textDocument: TextDocumentIdentifier(uri: uri)))) {
        case Nullable.Value(SymbolInformationsOrDocumentSymbols.AsDocumentSymbols(symbols)) => symbols
        case _ => None
    }
}

@Test
class DocumentSymbolTest {
    @TestCase
    func theOutlineIsNestedWithRangesInTheColumnsAgreedOn() {
        // arrange - the emoji is two UTF-16 units and four bytes
        let state = opened("/* 😀 */ class A {\n    func f() {}\n}\n")

        // act
        let symbols = documentSymbols(state, URI).getOrThrow()

        // assert
        @Expect(symbols.size, 1)
        let a = symbols[0]
        @Expect(a.name, "A")
        @Expect(a.selectionRange.start.character, 15)
        @Expect(a.range.end.line, 2)
        let f = a.children.getOrThrow()[0]
        @Expect(f.name, "f")
        @Expect(f.selectionRange.start.line, 1)
        @Expect(f.selectionRange.start.character, 9)
    }

    @TestCase
    func aDocumentTheServerDoesNotKnowHasNoOutline() {
        // act, assert
        @Expect(documentSymbols(ServerState(), URI).isNone())
    }
}
