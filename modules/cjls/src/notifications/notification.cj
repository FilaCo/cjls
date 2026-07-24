package cjls.notifications

import cjls.server.GlobalContext

public interface LspNotification<P> {
    static prop METHOD: String
    static func handle(params: P, ctx: GlobalContext): Unit
}