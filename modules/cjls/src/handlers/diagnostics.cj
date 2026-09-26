package cjls.handlers

import loupe.*
import loupe.vfs.VfsPath
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
        lsp.RelatedFullDocumentDiagnosticReport(items: documentDiagnostics(snap, VfsPath.fromUri(params.textDocument.uri))))
}

/**
 * The diagnostics of the document at `path`, as the snapshot has it: what a pull answers, and what
 * the server pushes to a client that cannot pull.
 */
func documentDiagnostics(snap: ServerSnapshot, path: VfsPath): Array<lsp.Diagnostic> {
    let file = snap.sourceFile(path) ?? return []
    let text = file.text(snap.analysis)
    diagnostics(snap.analysis, file.fileId(snap.analysis)).map {it => diagnostic(text, it, snap.encoding)}
}
