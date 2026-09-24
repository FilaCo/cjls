package cjls.handlers

import rope.Encoding
import cjls.lsp_types.*
import cjls.server.*

/**
 * Every handler of the server, one line each.
 */
public func router(): Router {
    Router()
        .route(InitializeRequestSpec(), handleInitialize)
        .route(ShutdownRequestSpec()) {_: Context<Unit> => ()}
        // on the read loop, so it is acted on the moment it is read rather than queued behind the
        // work it cancels
        .route(CancelNotificationSpec()) {ctx: Context<CancelParams> => ctx.client.cancel(ctx.params.id)}
        .route(DidOpenTextDocumentNotificationSpec(), handleDidOpen)
        .route(DidChangeTextDocumentNotificationSpec(), handleDidChange)
        .route(DidCloseTextDocumentNotificationSpec(), handleDidClose)
        .route(DocumentSymbolRequestSpec(), handleDocumentSymbol)
}

/**
 * What the server advertises, columns counted in `encoding`; it has to agree with `router()`.
 */
func capabilities(encoding: Encoding): ServerCapabilities {
    ServerCapabilities(
        positionEncoding: positionEncodingKind(encoding),
        textDocumentSync: TextDocumentSyncOptionsOrTextDocumentSyncKind.AsTextDocumentSyncOptions(
            TextDocumentSyncOptions(openClose: true, change: TextDocumentSyncKind.Incremental)),
        documentSymbolProvider: BooleanOrDocumentSymbolOptions.AsBoolean(true)
    )
}
