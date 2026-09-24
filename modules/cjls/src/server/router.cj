package cjls.server

import std.collection.HashMap
import stdx.serialization.serialization.*
import jsonrpc.ArrayOrObject
import cjls.lsp_types.*

/**
 * Every handler of the server, and the state they share - built the way an axum `Router` is:
 *
 * ```cangjie
 * Router()
 *     .withState(Database())
 *     .route(InitializeRequestSpec(), handleInitialize)
 *     .route(HoverRequestSpec(), handleHover)
 *     .route(CancelNotificationSpec()) {ctx: Context<CancelParams> => ctx.client.cancel(ctx.params.id)}
 * ```
 *
 * The spec gives the method and the types; a handler takes a context of the params and returns the
 * result, and the compiler holds it to both. `@LspHandler` makes a function of what it needs from
 * the context, params last, into one.
 *
 * The context says how the handler runs. With a `Context` it runs on the read loop itself, in
 * arrival order, with the `Database` to itself: it is how the inputs change, and nothing else is
 * read while it runs, so it must not take long. With a `ReadOnlyContext` it runs on a thread of its
 * own against a `DatabaseSnapshot` taken when its message arrived, so it sees every change before
 * it and none after, and any number run at once.
 */
public class Router {
    var db = Database()
    let requests = HashMap<String, RequestRoute>()
    let notifications = HashMap<String, NotificationRoute>()

    /**
     * The database the handlers share; a fresh one unless given.
     */
    public func withState(db: Database): Router {
        this.db = db
        this
    }

    /**
     * @throws IllegalArgumentException - if the method already has a handler
     */
    public func route<P, R>(spec: LspInboundRequest<P, R>, handler: (Context<P>) -> R): Router {
        add(requests, spec.method, RequestRoute.Exclusive({
            parts, params => spec.encodeResult(handler(parts.context(spec.decodeParams(params))))
        }))
    }

    /**
     * @throws IllegalArgumentException - if the method already has a handler
     */
    public func route<P>(spec: LspInboundNotification<P>, handler: (Context<P>) -> Unit): Router {
        add(notifications, spec.method, NotificationRoute.Exclusive({
            parts, params => handler(parts.context(spec.decodeParams(params)))
        }))
    }

    /**
     * @throws IllegalArgumentException - if the method already has a handler, or is one of the
     * lifecycle's: whatever arrives after it must see the state it leaves
     */
    public func route<P, R>(spec: LspInboundRequest<P, R>, handler: (ReadOnlyContext<P>) -> R): Router {
        refuseLifecycle(spec.method)
        add(requests, spec.method, RequestRoute.ReadOnly({
            parts, params => spec.encodeResult(handler(parts.context(spec.decodeParams(params))))
        }))
    }

    /**
     * @throws IllegalArgumentException - if the method already has a handler, or is one of the
     * lifecycle's: whatever arrives after it must see the state it leaves
     */
    public func route<P>(spec: LspInboundNotification<P>, handler: (ReadOnlyContext<P>) -> Unit): Router {
        refuseLifecycle(spec.method)
        add(notifications, spec.method, NotificationRoute.ReadOnly({
            parts, params => handler(parts.context(spec.decodeParams(params)))
        }))
    }

    private func add<T>(routes: HashMap<String, T>, method: String, route: T): Router {
        if (routes.contains(method)) {
            throw IllegalArgumentException("two handlers for \"${method}\"")
        }
        routes.add(method, route)
        this
    }
}

enum RequestRoute {
    | Exclusive((Parts, ?ArrayOrObject) -> DataModel)
    | ReadOnly((ReadOnlyParts, ?ArrayOrObject) -> DataModel)
}

enum NotificationRoute {
    | Exclusive((Parts, ?ArrayOrObject) -> Unit)
    | ReadOnly((ReadOnlyParts, ?ArrayOrObject) -> Unit)
}

private func refuseLifecycle(method: String): Unit {
    if (method == InitializeRequestSpec.METHOD || method == ShutdownRequestSpec.METHOD ||
        method == ExitNotificationSpec.METHOD) {
        throw IllegalArgumentException("\"${method}\" cannot be handled with a `ReadOnlyContext`")
    }
}
