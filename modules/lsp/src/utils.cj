package lsp

import stdx.encoding.json.stream.JsonWriter

extend JsonWriter {
    func writeJsonRpcField(): Unit {
        // The language server protocol always uses "2.0" as the jsonrpc version.
        writeValue("jsonrpc").writeValue("2.0")
    }
}
