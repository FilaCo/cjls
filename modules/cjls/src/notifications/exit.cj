package cjls.notifications

import stdx.encoding.json.stream.*
import stdxx.deriving.*
import cjls.lsp_types.*
import cjls.server.*
import cjls.macros.*
import lsp.*

@LspNotification[method: "exit"]
public class Exit {
    @LspHandle
    public static func handle(): Unit {
        throw UnsupportedException() // TODO: implement
    }
}
