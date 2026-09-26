package cjls.handlers

import stdxx.Nullable
import loupe.{highlight, TextRange}
import cjls.lsp_types as lsp
import cjls.server.*
import cjls.macros.LspHandler

/**
 * What every token of a document is, as far as its tree tells; `null` for a document the server
 * does not know. All of it every time: no `full/delta` yet (D16).
 */
@LspHandler[readonly]
func handleSemanticTokensFull(snap: ServerSnapshot, params: lsp.SemanticTokensParams): Nullable<lsp.SemanticTokens> {
    let file = fileOf(snap, params.textDocument.uri) ?? return Nullable.Null
    let text = file.text(snap.analysis)
    let tokens = highlight(snap.analysis, file.fileId(snap.analysis))
    Nullable.Value(semanticTokens(text, tokens, snap.encoding, snap.multilineTokens))
}

/**
 * The same, for the tokens a range of the document holds, even partly: what an editor shows.
 */
@LspHandler[readonly]
func handleSemanticTokensRange(snap: ServerSnapshot, params: lsp.SemanticTokensRangeParams): Nullable<lsp.SemanticTokens> {
    let file = fileOf(snap, params.textDocument.uri) ?? return Nullable.Null
    let text = file.text(snap.analysis)
    let range = TextRange(offsetOf(snap, file, params.range.start), offsetOf(snap, file, params.range.end))
    let tokens = highlight(snap.analysis, file.fileId(snap.analysis), range: range)
    Nullable.Value(semanticTokens(text, tokens, snap.encoding, snap.multilineTokens))
}
