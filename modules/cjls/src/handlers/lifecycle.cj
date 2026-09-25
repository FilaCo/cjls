package cjls.handlers

import rope.Encoding
import cjls.lsp_types.*
import cjls.server.*
import cjls.macros.LspHandler

@LspHandler
func handleInitialize(state: ServerState, params: InitializeParams): InitializeResult {
    state.encoding = negotiatedEncoding(params.capabilities)
    InitializeResult(capabilities: capabilities(state.encoding), serverInfo: ServerInfo(name: "cjls", version: "0.1.0"))
}

/**
 * UTF-8 if the client can count columns in it, since that is what the text is kept in; UTF-16
 * otherwise, which every client can.
 */
func negotiatedEncoding(capabilities: ClientCapabilities): Encoding {
    let offered: Array<PositionEncodingKind> = match (capabilities.general) {
        case Some(general) => general.positionEncodings ?? []
        case _ => []
    }
    if (offered.any {kind => kind.value == PositionEncodingKind.UTF8.value}) {
        Encoding.Utf8
    } else {
        Encoding.Utf16
    }
}

func positionEncodingKind(encoding: Encoding): PositionEncodingKind {
    match (encoding) {
        case Utf8 => PositionEncodingKind.UTF8
        case Utf16 => PositionEncodingKind.UTF16
        case Utf32 => PositionEncodingKind.UTF32
    }
}
