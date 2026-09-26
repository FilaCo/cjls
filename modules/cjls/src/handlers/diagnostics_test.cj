package cjls.handlers

import std.unittest.*
import std.unittest.testmacro.*
import cjls.lsp_types.*
import cjls.server.*

func pulled(snap: ServerSnapshot, uri!: String = URI): Array<Diagnostic> {
    let params = DocumentDiagnosticParams(textDocument: TextDocumentIdentifier(uri: uri))
    match (handleDocumentDiagnostic(snap, params)) {
        case DocumentDiagnosticReport.AsRelatedFullDocumentDiagnosticReport(report) => report.items
        case _ => throw AssertException("not a full report")
    }
}

@Test
class DocumentDiagnosticTest {
    @TestCase
    func aSyntaxErrorIsReportedInTheColumnsAgreedOn() {
        // arrange - the emoji is two UTF-16 units and four bytes
        let state = opened("/* 😀 */ class A {")

        // act
        let items = pulled(state.snapshot())

        // assert
        @Expect(items.size, 1)
        @Expect(items[0].range.start.line, 0)
        @Expect(items[0].range.start.character, 18)
        @Expect(items[0].range.end.character, 18)
        @Expect(match (items[0].severity) {
            case Some(DiagnosticSeverity.Error) => true
            case _ => false
        })
        @Expect(items[0].source, "cjls")
    }

    @TestCase
    func aDocumentTheServerDoesNotKnowHasNothingWrong() {
        // act
        let items = pulled(ServerState().snapshot())

        // assert
        @Expect(items.size, 0)
    }
}
