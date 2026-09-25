package cjls.handlers

import stdxx.Nullable
import loupe.fileStructure
import cjls.lsp_types.*
import cjls.server.*
import cjls.macros.LspHandler

/**
 * The outline of a document, nested; `null` for a document the server does not know.
 */
@LspHandler[readonly]
func handleDocumentSymbol(snap: ServerSnapshot, params: DocumentSymbolParams): Nullable<SymbolInformationsOrDocumentSymbols> {
    let file = fileOf(snap, params.textDocument.uri) ?? return Nullable.Null
    let text = file.text(snap.analysis)
    let structure = fileStructure(snap.analysis, file.fileId(snap.analysis))
    Nullable.Value(SymbolInformationsOrDocumentSymbols.AsDocumentSymbols(
        structure.map {node => documentSymbol(text, node, snap.encoding)}))
}
