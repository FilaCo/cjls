package cjls

import lsp.*

public struct InitializeRequest <: LspRequest<InitializeParams, InitializeResult> {
    @Frozen
    public static func method(): String {
        "initialize"
    }
}
