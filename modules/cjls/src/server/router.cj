package cjls.server

import stdx.log.*
import jsonrpc.*
import cjls.lsp_types.*

/**
 * Where the server is in the protocol's lifecycle. Every handler runs the same way whatever the
 * method; what the lifecycle decides is only whether a message reaches its handler at all.
 */
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
 * The lifecycle is the protocol's, the same for every server, so the router keeps it by the
 * methods alone: a successful `initialize` starts the server, a successful `shutdown` stops it
 * taking requests, `exit` ends the connection. What each of them does besides is its handler's.
 */
class Router <: Handler {
    private var lifecycle = Lifecycle.Uninitialized
    private var shutDownCleanly = false

    Router(private let routes: Routes, private let client: Client) {}

    prop state: Lifecycle {
        get() {
            lifecycle
        }
    }

    /**
     * What the process exits with: success only for an `exit` that followed a `shutdown`.
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
        if (let Some(refusal) <- refusalOf(request.method)) {
            request.respond(ResultOrError.Error(refusal))
            return
        }
        let route = match (routes.requests.get(request.method)) {
            case Some(route) => route
            case None =>
                request.respond(
                    ResultOrError.Error(ResponseError(ErrorCode.METHOD_NOT_FOUND, "no handler for \"${request.method}\"")))
                return
        }

        match (route) {
            case Exclusive(handler) =>
                let answer = try {
                    ResultOrError.Result(handler(request.params, Scope(routes.db, client, request.cancellation)))
                } catch (e: Exception) {
                    ResultOrError.Error(responseErrorOf(e))
                }
                request.respond(answer)
                if (answer.isResult()) {
                    advance(request.method)
                }
            case ReadOnly(handler) =>
                // taken here, on the read loop, so it holds what every message before this one did
                let scope = ReadOnlyScope(routes.db.snapshot(), client, request.cancellation)
                spawn {
                    request.respondWith {=> ResultOrError.Result(handler(request.params, scope))}
                }
        }
    }

    public func onNotification(method: String, params: ?ArrayOrObject): Unit {
        if (method == ExitNotificationSpec.METHOD) {
            try {
                dispatch(method, params)
            } finally {
                exit()
            }
            return
        }
        match (lifecycle) {
            // before `initialize` and after `shutdown`, notifications are dropped - `exit` aside
            case Uninitialized | ShuttingDown | Exited =>
                getGlobalLogger().debug("dropped \"${method}\" - the server is ${describe(lifecycle)}")
            case Initialized => dispatch(method, params)
        }
    }

    private func dispatch(method: String, params: ?ArrayOrObject): Unit {
        let route = match (routes.notifications.get(method)) {
            case Some(route) => route
            case None =>
                // `$/` notifications are the protocol's own, and a server is free to ignore them
                getGlobalLogger().debug("no handler for \"${method}\"")
                return
        }

        // nobody cancels a notification
        let cancellation = CancellationToken()
        match (route) {
            // a throw goes up to the connection, which logs it; nobody is waiting on an answer
            case Exclusive(handler) => handler(params, Scope(routes.db, client, cancellation))
            case ReadOnly(handler) =>
                let scope = ReadOnlyScope(routes.db.snapshot(), client, cancellation)
                spawn {
                    // a thread that throws dumps its stack even when nobody reads its future
                    try {
                        handler(params, scope)
                    } catch (e: Exception) {
                        getGlobalLogger().error("notification \"${method}\" failed", [("cause", e)])
                    }
                }
        }
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
        } else if (method == ShutdownRequestSpec.METHOD) {
            lifecycle = ShuttingDown
        }
    }

    private func exit(): Unit {
        shutDownCleanly = match (lifecycle) {
            case ShuttingDown => true
            case _ => false
        }
        lifecycle = Exited
        client.close()
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
