package cjls.handlers

import cjls.lsp_types.*
import cjls.server.*
import cjls.macros.LspHandler

@LspHandler[readonly]
func handleDocumentDiagnostic(snap: ServerSnapshot, params: DocumentDiagnosticParams): DocumentDiagnosticReport {
    throw Exception()
}
