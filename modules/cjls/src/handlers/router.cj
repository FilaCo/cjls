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
        .route(DocumentDiagnosticRequestSpec(), handleDocumentDiagnostic)
        .route(SemanticTokensRequestSpec(), handleSemanticTokensFull)
        .route(SemanticTokensRangeRequestSpec(), handleSemanticTokensRange)
        .publishDiagnostics(documentDiagnostics)
}

/**
 * What the server advertises, columns counted in `encoding`; it has to agree with `router()`.
 */
func capabilities(encoding: Encoding): ServerCapabilities {
    ServerCapabilities(
        positionEncoding: positionEncodingKind(encoding),
        textDocumentSync: TextDocumentSyncOptionsOrTextDocumentSyncKind.AsTextDocumentSyncOptions(
            TextDocumentSyncOptions(openClose: true, change: TextDocumentSyncKind.Incremental)),
        documentSymbolProvider: BooleanOrDocumentSymbolOptions.AsBoolean(true),
        // a file's diagnostics are its own, and nothing is reported for files not open (D14)
        diagnosticProvider: DiagnosticOptionsOrDiagnosticRegistrationOptions.AsDiagnosticOptions(
            DiagnosticOptions(interFileDependencies: false, workspaceDiagnostics: false)),
        // no `full/delta` until the server keeps what it sent (D19)
        semanticTokensProvider: SemanticTokensOptionsOrSemanticTokensRegistrationOptions.AsSemanticTokensOptions(
            SemanticTokensOptions(legend: semanticTokensLegend(),
                range: BooleanOrSemanticTokensOptionsRange.AsBoolean(true),
                full: BooleanOrSemanticTokensFullDelta.AsBoolean(true)))
    )
}
