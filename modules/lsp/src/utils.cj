package lsp

import std.io.ByteBuffer
import stdx.encoding.json.stream.*

extend JsonWriter {
    func writeJsonRpcField(): Unit {
        // The language server protocol always uses "2.0" as the jsonrpc version.
        writeName("jsonrpc").writeValue("2.0")
    }
}

func toJsonString<T>(v: T): String where T <: JsonSerializable {
    let bb = ByteBuffer()
    let jw = JsonWriter(bb)
    v.toJson(jw)
    jw.flush()
    String.fromUtf8(bb.bytes())
}
