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
func handleDocumentSymbol(db: DatabaseSnapshot, params: DocumentSymbolParams): Nullable<SymbolInformationsOrDocumentSymbols> {
    let file = fileOf(db, params.textDocument.uri) ?? return Nullable.Null
    let text = file.text(db.analysis)
    let structure = fileStructure(db.analysis, file.fileId(db.analysis))
    Nullable.Value(SymbolInformationsOrDocumentSymbols.AsDocumentSymbols(
        structure.map {node => documentSymbol(text, node, db.encoding)}))
}
