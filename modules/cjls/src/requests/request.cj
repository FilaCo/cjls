package cjls.requests

import cjls.server.GlobalContext

public interface LspRequest<P, R> {
    static prop METHOD: String
    static func handle(params: P, ctx: GlobalContext): R
}
