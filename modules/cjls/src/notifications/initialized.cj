package cjls.notifications

import stdx.encoding.json.stream.*
import stdxx.deriving.*
import cjls.lsp_types.*
import cjls.macros.*
import lsp.*

@LspNotification["initialized"]
public struct Initialized {
    @LspHandle
    public static func handle(): Unit {
        throw UnsupportedException() // TODO: implement
    }
}
