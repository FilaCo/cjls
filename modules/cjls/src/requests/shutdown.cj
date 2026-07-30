package cjls.requests

import stdx.encoding.json.stream.*
import stdxx.deriving.*
import cjls.lsp_types.*
import cjls.macros.*
import lsp.*

@LspRequest["shutdown"]
public struct Shutdown {
    @LspHandle
    public static func handle(): Unit {
        throw UnsupportedException() // TODO: implement
    }
}
