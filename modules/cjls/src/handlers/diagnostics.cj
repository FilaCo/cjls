package cjls.handlers

import loupe.*
import cjls.lsp_types as lsp
import cjls.server.*
import cjls.macros.LspHandler

/**
 * What is wrong in a document, all of it every time: no `resultId` yet (Q9). A document the server
 * does not know has nothing wrong. The files changing under it is the server's to answer (S5), with
 * `ServerCancelled` so the client pulls again (D14).
 */
@LspHandler[readonly]
func handleDocumentDiagnostic(snap: ServerSnapshot, params: lsp.DocumentDiagnosticParams): lsp.DocumentDiagnosticReport {
    lsp.DocumentDiagnosticReport.AsRelatedFullDocumentDiagnosticReport(
        lsp.RelatedFullDocumentDiagnosticReport(items: documentDiagnostics(snap, params.textDocument.uri)))
}

/**
 * The diagnostics of the document at `uri`, as the snapshot has it.
 */
func documentDiagnostics(snap: ServerSnapshot, uri: lsp.DocumentUri): Array<lsp.Diagnostic> {
    let file = fileOf(snap, uri) ?? return []
    let text = file.text(snap.analysis)
    diagnostics(snap.analysis, file.fileId(snap.analysis)).map {it => diagnostic(text, it, snap.encoding)}
}
