package cjls

import cjls.lsp_types.*
import cjls.server.*

/**
 * Every handler of the server. The lifecycle's own are registered with `route`, the way the
 * router insists on: whatever arrives after them must see the state they leave.
 */
func routes(): Routes {
    Routes()
        .route(InitializeRequestSpec(), handleInitialize)
        .route(ShutdownRequestSpec()) {_ => ()}
        // `route`, so it is acted on the moment it is read rather than queued behind the work it cancels
        .route(CancelNotificationSpec()) {ctx => ctx.client.cancel(ctx.params.id)}
}

/**
 * Nothing is advertised yet: a client connects, and has nothing to ask for.
 */
func handleInitialize(_: Context<InitializeParams>): InitializeResult {
    InitializeResult(capabilities: ServerCapabilities(), serverInfo: ServerInfo(name: "cjls", version: "0.1.0"))
}
