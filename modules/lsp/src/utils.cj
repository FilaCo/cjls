package lsp

import stdx.encoding.json.stream.JsonWriter

extend JsonWriter {
    @Frozen
    func writeJsonRpcField(): Unit {
        // The language server protocol always uses "2.0" as the jsonrpc version.
        writeName("jsonrpc").writeValue("2.0")
    }
}
