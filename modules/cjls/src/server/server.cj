package cjls.server

import std.collection.*
import std.deriving.*
import std.time.MonoTime
import stdx.log.*
import stdx.serialization.serialization.*
import calca.Cancelled
import jsonrpc.*
import loupe.vfs.VfsPath
import cjls.lsp_types.*

@Derive[Equatable]
enum Lifecycle {
    | Uninitialized
    | Initialized
    | ShuttingDown
    | Exited
}

/**
 * The `Handler` a connection hands inbound messages to: it keeps the lifecycle, finds each
 * message's route, and runs it the way it was registered.
 *
 * The lifecycle is the protocol's, the same for every server, so it is kept by the methods alone:
 * a successful `initialize` starts the server, a successful `shutdown` stops it taking requests,
 * `exit` ends the connection. What each of them does besides is its handler's.
 */
class Server <: Handler {
    private var lifecycle = Lifecycle.Uninitialized
    private var shutDownCleanly = false

    private let push: ?DiagnosticsPush

    Server(private let router: Router, private let client: Client, private let logger: Logger) {
        push = router.diagnostics.map {diagnostics => DiagnosticsPush(diagnostics, client, logger)}
    }

    prop state: Lifecycle {
        get() {
            lifecycle
        }
    }

    /**
     * Success only for an `exit` that followed a `shutdown`.
     */
    prop exitCode: Int64 {
        get() {
            if (shutDownCleanly) {
                0
            } else {
                1
            }
        }
    }

    public func onRequest(request: InboundRequest): Unit {
        let logger = logger.withAttrs([("method", request.method), ("id", request.id.toString())])
        if (let Some(refusal) <- refusalOf(request.method)) {
            logger.debug("refused", [("reason", refusal.message)])
            request.respond(ResultOrError.Error(refusal))
            return
        }
        match (router.requests.get(request.method)) {
            case None =>
                logger.debug("no handler")
                request.respond(
                    ResultOrError.Error(ResponseError(ErrorCode.METHOD_NOT_FOUND, "no handler for \"${request.method}\"")))
            case Some(Exclusive(handler)) =>
                let parts = Parts(router.state, client, request.cancellation, logger)
                if (writing {answer(request, logger) {handler(parts, request.params)}}) {
                    advance(request.method)
                }
            case Some(ReadOnly(handler)) =>
                // taken here, on the read loop, so it holds what every message before this one did
                let cancellation = request.cancellation
                let snapshot = router.state.snapshot(cancelledBy: {=> cancellation.isCancelled})
                let parts = ReadOnlyParts(snapshot, client, cancellation, logger)
                spawn {
                    answer(request, logger) {handler(parts, request.params)}
                }
        }
    }

    public func onNotification(method: String, params: ?ArrayOrObject): Unit {
        let logger = logger.withAttrs([("method", method)])
        if (method == ExitNotificationSpec.METHOD) {
            dispatch(method, params, logger)
            exit()
            return
        }
        match (lifecycle) {
            case Initialized => dispatch(method, params, logger)
            case _ => logger.debug("dropped", [("reason", "the server is ${describe(lifecycle)}")])
        }
    }

    private func dispatch(method: String, params: ?ArrayOrObject, logger: Logger): Unit {
        let cancellation = CancellationToken()
        match (router.notifications.get(method)) {
            // the `$/` ones are the protocol's own, and a server is free to ignore them
            case None => logger.debug("no handler")
            case Some(Exclusive(handler)) =>
                writing {run(logger) {handler(Parts(router.state, client, cancellation, logger), params)}}
            case Some(ReadOnly(handler)) =>
                let parts = ReadOnlyParts(router.state.snapshot(), client, cancellation, logger)
                spawn {
                    run(logger) {handler(parts, params)}
                }
        }
    }

    /**
     * Runs a `Context` handler, then the work its changes call for (S7): a client that cannot pull
     * is pushed nothing for the documents just closed, at once, and the diagnostics of every open
     * document, from a snapshot taken here, once the files changed or a document opened.
     */
    private func writing<T>(handler: () -> T): T {
        let state = router.state
        let openBefore = HashSet<VfsPath>(state.openDocuments.keys())
        let result = handler()
        let filesChanged = state.takeFilesChanged()
        let push = push ?? return result
        if (!state.pushesDiagnostics) {
            return result
        }
        for (path in openBefore where !state.openDocuments.contains(path)) {
            push.clear(path)
        }
        let opened = state.openDocuments.keys().iterator().any {path => !openBefore.contains(path)}
        if (filesChanged || opened) {
            let documents = collectArray(state.openDocuments)
            push.schedule(state.snapshot(), documents)
        }
        result
    }

    private func refusalOf(method: String): ?ResponseError {
        match (lifecycle) {
            case Uninitialized where method != InitializeRequestSpec.METHOD =>
                ResponseError(ErrorCode.SERVER_NOT_INITIALIZED, "the server is not initialized yet")
            case Initialized where method == InitializeRequestSpec.METHOD =>
                ResponseError(ErrorCode.INVALID_REQUEST, "the server is already initialized")
            case ShuttingDown | Exited => ResponseError(ErrorCode.INVALID_REQUEST, "the server is shutting down")
            case _ => None
        }
    }

    private func advance(method: String): Unit {
        if (method == InitializeRequestSpec.METHOD) {
            lifecycle = Initialized
            logger.info("initialized")
        } else if (method == ShutdownRequestSpec.METHOD) {
            lifecycle = ShuttingDown
            logger.info("shutting down")
        }
    }

    private func exit(): Unit {
        shutDownCleanly = lifecycle == ShuttingDown
        lifecycle = Exited
        logger.info("exiting", [("clean", shutDownCleanly)])
        client.close()
    }
}

/**
 * Why a query of `request` was `Cancelled`: the client cancelled the request, or the files changed
 * under it, which the client may ask again for — and a diagnostic pull asks again at once, rather
 * than keep the diagnostics it had (D14).
 */
private func cancelledError(request: InboundRequest, logger: Logger): ResponseError {
    if (request.cancellation.isCancelled) {
        logger.debug("cancelled", [("reason", "the client cancelled it")])
        ResponseError(ErrorCode.REQUEST_CANCELLED, "the request was cancelled")
    } else if (request.method == DocumentDiagnosticRequestSpec.METHOD) {
        logger.debug("cancelled", [("reason", "the content was modified")])
        ResponseError(ErrorCode.SERVER_CANCELLED, "the content was modified",
            data: DiagnosticServerCancellationData(retriggerRequest: true).serialize())
    } else {
        logger.debug("cancelled", [("reason", "the content was modified")])
        ResponseError(ErrorCode.CONTENT_MODIFIED, "the content was modified")
    }
}

/**
 * Answers `request` with what `handler` gives; a query cancelled midway is answered
 * `RequestCancelled` or `ContentModified`, see `cancelledError`. Never throws, so it is a safe body for a `spawn`:
 * a thread that throws dumps its stack even when nobody reads its future.
 *
 * @return whether the handler succeeded
 */
private func answer(request: InboundRequest, logger: Logger, handler: () -> DataModel): Bool {
    let start = MonoTime.now()
    let answer = try {
        ResultOrError.Result(handler())
    } catch (_: Cancelled) {
        ResultOrError.Error(cancelledError(request, logger))
    } catch (e: Exception) {
        logFailure(logger, e)
        ResultOrError.Error(responseErrorOf(e))
    }
    request.respond(answer)
    logger.debug("answered", [("took", MonoTime.now() - start)])
    answer.isResult()
}

/**
 * Runs a notification's handler; nobody waits on its answer, so a failure is only logged.
 */
private func run(logger: Logger, handler: () -> Unit): Unit {
    let start = MonoTime.now()
    try {
        handler()
        logger.debug("handled", [("took", MonoTime.now() - start)])
    } catch (_: Cancelled) {
        logger.debug("cancelled", [("reason", "the content was modified")])
    } catch (e: Exception) {
        logFailure(logger, e)
    }
}

/**
 * An `RpcException` is an answer the handler chose, so its message is enough; anything else is a
 * bug, and gets its stack.
 */
private func logFailure(logger: Logger, e: Exception): Unit {
    match (e) {
        case rpc: RpcException => logger.warn("failed", [("error", rpc.message)])
        case _ => logger.error("failed", [("cause", e)])
    }
}

private func describe(lifecycle: Lifecycle): String {
    match (lifecycle) {
        case Uninitialized => "not initialized yet"
        case Initialized => "running"
        case ShuttingDown => "shutting down"
        case Exited => "exited"
    }
}
