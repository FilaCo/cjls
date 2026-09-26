package cjls.handlers

import cjls.lsp_types as lsp
import cjls.server.*
import cjls.macros.LspHandler

@LspHandler[readonly]
func handleDocumentDiagnostic(snap: ServerSnapshot, params: lsp.DocumentDiagnosticParams): lsp.DocumentDiagnosticReport {
    throw Exception()
}
