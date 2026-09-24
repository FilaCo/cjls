package cjls.handlers

import cjls.lsp_types.*
import cjls.server.*

/**
 * Every handler of the server, one line each.
 */
public func router(): Router {
    Router()
        .route(InitializeRequestSpec(), handleInitialize)
        .route(ShutdownRequestSpec()) {_: Context, _ => ()}
        // on the read loop, so it is acted on the moment it is read rather than queued behind the
        // work it cancels
        .route(CancelNotificationSpec()) {ctx: Context, params => ctx.client.cancel(params.id)}
}

/**
 * What the server advertises; it has to agree with `router()`.
 */
func capabilities(): ServerCapabilities {
    ServerCapabilities()
}
