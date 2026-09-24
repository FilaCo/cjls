package cjls.server

import std.collection.HashMap
import stdx.serialization.serialization.*
import stdxx.*
import cjls.lsp_types.*

/**
 * Every handler of the server, and the state they share - built the way an axum `Router` is:
 *
 * ```cangjie
 * Routes()
 *     .state(Database())
 *     .route(InitializeRequestSpec(), handleInitialize)
 *     .readonly(HoverRequestSpec()) { ctx => hoverAt(ctx.db, ctx.params) }
 * ```
 *
 * The spec gives the method and the types: the handler takes a context of its params and returns
 * its result, and the compiler holds it to both.
 *
 * `route` runs a handler on the read loop itself, in arrival order, with the `Database` to itself:
 * it is how the inputs change - a document opened or edited, the server initialized - and nothing
 * else is read while it runs, so it must not take long. `readonly` runs it on a thread of its own
 * against a `DatabaseSnapshot` taken when its message arrived: it sees every change before it and
 * none after, and any number of them run at once. Which of the two the handler is written for is in
 * the type of its context, so registering it with the other does not compile.
 */
public class Routes {
    var db = Database()
    let requests = HashMap<String, RequestRoute>()
    let notifications = HashMap<String, NotificationRoute>()

    /**
     * The database the handlers share; a fresh one unless given.
     */
    public func state(db: Database): Routes {
        this.db = db
        this
    }

    /**
     * @throws IllegalArgumentException - if the method already has a handler
     */
    public func route<P, R>(spec: LspInboundRequest<P, R>, handler: (Context<P>) -> R): Routes {
        addRequest(spec.method, RequestRoute.Exclusive({
            params, scope => spec.encodeResult(handler(scope.context(spec.decodeParams(params))))
        }))
    }

    /**
     * @throws IllegalArgumentException - if the method already has a handler
     */
    public func route<P>(spec: LspInboundNotification<P>, handler: (Context<P>) -> Unit): Routes {
        addNotification(spec.method, NotificationRoute.Exclusive({
            params, scope => handler(scope.context(spec.decodeParams(params)))
        }))
    }

    /**
     * @throws IllegalArgumentException - if the method already has a handler, or is one of the
     * lifecycle's: whatever arrives after it must see the state it leaves
     */
    public func readonly<P, R>(spec: LspInboundRequest<P, R>, handler: (ReadOnlyContext<P>) -> R): Routes {
        refuseLifecycle(spec.method)
        addRequest(spec.method, RequestRoute.ReadOnly({
            params, scope => spec.encodeResult(handler(scope.context(spec.decodeParams(params))))
        }))
    }

    /**
     * @throws IllegalArgumentException - if the method already has a handler, or is one of the
     * lifecycle's: whatever arrives after it must see the state it leaves
     */
    public func readonly<P>(spec: LspInboundNotification<P>, handler: (ReadOnlyContext<P>) -> Unit): Routes {
        refuseLifecycle(spec.method)
        addNotification(spec.method, NotificationRoute.ReadOnly({
            params, scope => handler(scope.context(spec.decodeParams(params)))
        }))
    }

    private func addRequest(method: String, route: RequestRoute): Routes {
        if (requests.contains(method)) {
            throw IllegalArgumentException("two handlers for \"${method}\"")
        }
        requests.add(method, route)
        this
    }

    private func addNotification(method: String, route: NotificationRoute): Routes {
        if (notifications.contains(method)) {
            throw IllegalArgumentException("two handlers for \"${method}\"")
        }
        notifications.add(method, route)
        this
    }
}

enum RequestRoute {
    | Exclusive((?ArrayOrObject, Scope) -> DataModel)
    | ReadOnly((?ArrayOrObject, ReadOnlyScope) -> DataModel)
}

enum NotificationRoute {
    | Exclusive((?ArrayOrObject, Scope) -> Unit)
    | ReadOnly((?ArrayOrObject, ReadOnlyScope) -> Unit)
}

private func refuseLifecycle(method: String): Unit {
    if (method == InitializeRequestSpec.METHOD || method == ShutdownRequestSpec.METHOD || method == ExitNotificationSpec.METHOD) {
        throw IllegalArgumentException("\"${method}\" cannot be `readonly`")
    }
}
