package cjls.handlers

import rope.Encoding
import cjls.lsp_types as lsp
import cjls.server.*
import cjls.macros.LspHandler

/**
 * The server's version, as `modules/cjls/cjpm.toml` has it: `cog bump` rewrites both.
 */
const VERSION = "0.1.0"

@LspHandler
func handleInitialize(state: ServerState, params: lsp.InitializeParams): lsp.InitializeResult {
    state.encoding = negotiatedEncoding(params.capabilities)
    state.pushesDiagnostics = !pullsDiagnostics(params.capabilities)
    state.multilineTokens = takesMultilineTokens(params.capabilities)
    lsp.InitializeResult(capabilities: capabilities(state.encoding),
        serverInfo: lsp.ServerInfo(name: "cjls", version: VERSION))
}

/**
 * UTF-8 if the client can count columns in it, since that is what the text is kept in; UTF-16
 * otherwise, which every client can.
 */
func negotiatedEncoding(capabilities: lsp.ClientCapabilities): Encoding {
    let offered = capabilities.general.flatMap {general => general.positionEncodings} ?? []
    if (offered.any {kind => kind.value == lsp.PositionEncodingKind.UTF8.value}) {
        Encoding.Utf8
    } else {
        Encoding.Utf16
    }
}

/**
 * Whether the client asks for diagnostics itself (`textDocument/diagnostic`); one that does not is
 * pushed them (D14).
 */
func pullsDiagnostics(capabilities: lsp.ClientCapabilities): Bool {
    capabilities.textDocument.flatMap {textDocument => textDocument.diagnostic}.isSome()
}

/**
 * Whether the client takes a semantic token spanning lines; `false` unless it says so, as LSP has it.
 */
func takesMultilineTokens(capabilities: lsp.ClientCapabilities): Bool {
    capabilities.textDocument.flatMap {textDocument => textDocument.semanticTokens}.flatMap {
        semanticTokens => semanticTokens.multilineTokenSupport
    } ?? false
}

func positionEncodingKind(encoding: Encoding): lsp.PositionEncodingKind {
    match (encoding) {
        case Utf8 => lsp.PositionEncodingKind.UTF8
        case Utf16 => lsp.PositionEncodingKind.UTF16
        case Utf32 => lsp.PositionEncodingKind.UTF32
    }
}
