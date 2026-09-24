package cjls.handlers

import cjls.lsp_types.*
import cjls.server.*
import cjls.macros.LspHandler

@LspHandler
func handleInitialize(_: InitializeParams): InitializeResult {
    InitializeResult(capabilities: capabilities(), serverInfo: ServerInfo(name: "cjls", version: "0.1.0"))
}
