package cjls.notifications

import stdx.encoding.json.stream.{JsonSerializable, JsonDeserializable}
import cjls.server.GlobalContext

public interface LspNotification<P>
    // where P <: JsonDeserializable<P>
{
    static prop METHOD: String
    static func handle(params: P, ctx: GlobalContext): Unit
}
