package cjls.notifications

import stdx.encoding.json.stream.*
import stdxx.deriving.*
import cjls.lsp_types.TextDocumentItem
import cjls.macros.*

@LspNotification[method: "textDocument/didOpen", params: DidOpenTextDocumentParams]
public struct DidOpenTextDocument {
    @LspHandle
    public static func handle(params: DidOpenTextDocumentParams): Unit {}
}

@DeriveExt[Json]
public struct DidOpenTextDocumentParams {
    public DidOpenTextDocumentParams(public let textDocument: TextDocumentItem) {}
}
