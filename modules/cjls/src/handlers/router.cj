package cjls.handlers

import rope.Encoding
import cjls.lsp_types as lsp
import cjls.server.*

/**
 * Every handler of the server, one line each.
 */
public func router(): Router {
    Router()
        .route(lsp.InitializeRequestSpec(), handleInitialize)
        .route(lsp.ShutdownRequestSpec()) {_: Context<Unit> => ()}
        // on the read loop, so it is acted on the moment it is read rather than queued behind the
        // work it cancels
        .route(lsp.CancelNotificationSpec()) {ctx: Context<lsp.CancelParams> => ctx.client.cancel(ctx.params.id)}
        .route(lsp.DidOpenTextDocumentNotificationSpec(), handleDidOpen)
        .route(lsp.DidChangeTextDocumentNotificationSpec(), handleDidChange)
        .route(lsp.DidCloseTextDocumentNotificationSpec(), handleDidClose)
        .route(lsp.DocumentSymbolRequestSpec(), handleDocumentSymbol)
        .route(lsp.DocumentDiagnosticRequestSpec(), handleDocumentDiagnostic)
        .publishDiagnostics(documentDiagnostics)
}

/**
 * What the server advertises, columns counted in `encoding`; it has to agree with `router()`.
 */
func capabilities(encoding: Encoding): lsp.ServerCapabilities {
    lsp.ServerCapabilities(
        positionEncoding: positionEncodingKind(encoding),
        textDocumentSync: lsp.TextDocumentSyncOptionsOrTextDocumentSyncKind.AsTextDocumentSyncOptions(
            lsp.TextDocumentSyncOptions(openClose: true, change: lsp.TextDocumentSyncKind.Incremental)),
        documentSymbolProvider: lsp.BooleanOrDocumentSymbolOptions.AsBoolean(true),
        // a file's diagnostics are its own, and nothing is reported for files not open (D14)
        diagnosticProvider: lsp.DiagnosticOptionsOrDiagnosticRegistrationOptions.AsDiagnosticOptions(
            lsp.DiagnosticOptions(interFileDependencies: false, workspaceDiagnostics: false))
    )
}
