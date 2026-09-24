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
 *     .readonly(HoverRequestSpec(), handleHover)
 *     .route(CancelNotificationSpec()) {client: Client, params => client.cancel(params.id)}
 * ```
 *
 * The spec gives the method and the types. A handler takes its params last, before them up to three
 * of what it needs from the server - `Database` or `DatabaseSnapshot`, `Client`,
 * `CancellationToken`, `Logger`, or the whole `Context` - and returns its result; the compiler holds
 * it to all of them. There is an overload per count because Cangjie has no variadic generics.
 *
 * `route` runs a handler on the read loop itself, in arrival order, with the `Database` to itself:
 * it is how the inputs change, and nothing else is read while it runs, so it must not take long.
 * `readonly` runs it on a thread of its own against a `DatabaseSnapshot` taken when its message
 * arrived, so it sees every change before it and none after, and any number run at once. A handler
 * asking for the `Database` does not compile under `readonly`.
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

    public func route<P, R>(spec: LspInboundRequest<P, R>, handler: (P) -> R): Router {
        exclusive(spec) {_, params => handler(params)}
    }

    public func route<A, P, R>(spec: LspInboundRequest<P, R>, handler: (A, P) -> R): Router
        where A <: FromContext<A> {
        exclusive(spec) {ctx, params => handler(A.from(ctx), params)}
    }

    public func route<A, B, P, R>(spec: LspInboundRequest<P, R>, handler: (A, B, P) -> R): Router
        where A <: FromContext<A>, B <: FromContext<B> {
        exclusive(spec) {ctx, params => handler(A.from(ctx), B.from(ctx), params)}
    }

    public func route<A, B, C, P, R>(spec: LspInboundRequest<P, R>, handler: (A, B, C, P) -> R): Router
        where A <: FromContext<A>, B <: FromContext<B>, C <: FromContext<C> {
        exclusive(spec) {ctx, params => handler(A.from(ctx), B.from(ctx), C.from(ctx), params)}
    }

    public func route<P>(spec: LspInboundNotification<P>, handler: (P) -> Unit): Router {
        exclusive(spec) {_, params => handler(params)}
    }

    public func route<A, P>(spec: LspInboundNotification<P>, handler: (A, P) -> Unit): Router
        where A <: FromContext<A> {
        exclusive(spec) {ctx, params => handler(A.from(ctx), params)}
    }

    public func route<A, B, P>(spec: LspInboundNotification<P>, handler: (A, B, P) -> Unit): Router
        where A <: FromContext<A>, B <: FromContext<B> {
        exclusive(spec) {ctx, params => handler(A.from(ctx), B.from(ctx), params)}
    }

    public func route<A, B, C, P>(spec: LspInboundNotification<P>, handler: (A, B, C, P) -> Unit): Router
        where A <: FromContext<A>, B <: FromContext<B>, C <: FromContext<C> {
        exclusive(spec) {ctx, params => handler(A.from(ctx), B.from(ctx), C.from(ctx), params)}
    }

    public func readonly<P, R>(spec: LspInboundRequest<P, R>, handler: (P) -> R): Router {
        concurrent(spec) {_, params => handler(params)}
    }

    public func readonly<A, P, R>(spec: LspInboundRequest<P, R>, handler: (A, P) -> R): Router
        where A <: FromReadOnlyContext<A> {
        concurrent(spec) {ctx, params => handler(A.from(ctx), params)}
    }

    public func readonly<A, B, P, R>(spec: LspInboundRequest<P, R>, handler: (A, B, P) -> R): Router
        where A <: FromReadOnlyContext<A>, B <: FromReadOnlyContext<B> {
        concurrent(spec) {ctx, params => handler(A.from(ctx), B.from(ctx), params)}
    }

    public func readonly<A, B, C, P, R>(spec: LspInboundRequest<P, R>, handler: (A, B, C, P) -> R): Router
        where A <: FromReadOnlyContext<A>, B <: FromReadOnlyContext<B>, C <: FromReadOnlyContext<C> {
        concurrent(spec) {ctx, params => handler(A.from(ctx), B.from(ctx), C.from(ctx), params)}
    }

    public func readonly<P>(spec: LspInboundNotification<P>, handler: (P) -> Unit): Router {
        concurrent(spec) {_, params => handler(params)}
    }

    public func readonly<A, P>(spec: LspInboundNotification<P>, handler: (A, P) -> Unit): Router
        where A <: FromReadOnlyContext<A> {
        concurrent(spec) {ctx, params => handler(A.from(ctx), params)}
    }

    public func readonly<A, B, P>(spec: LspInboundNotification<P>, handler: (A, B, P) -> Unit): Router
        where A <: FromReadOnlyContext<A>, B <: FromReadOnlyContext<B> {
        concurrent(spec) {ctx, params => handler(A.from(ctx), B.from(ctx), params)}
    }

    public func readonly<A, B, C, P>(spec: LspInboundNotification<P>, handler: (A, B, C, P) -> Unit): Router
        where A <: FromReadOnlyContext<A>, B <: FromReadOnlyContext<B>, C <: FromReadOnlyContext<C> {
        concurrent(spec) {ctx, params => handler(A.from(ctx), B.from(ctx), C.from(ctx), params)}
    }

    /**
     * @throws IllegalArgumentException - if the method already has a handler
     */
    private func exclusive<P, R>(spec: LspInboundRequest<P, R>, handler: (Context, P) -> R): Router {
        add(requests, spec.method, RequestRoute.Exclusive({
            ctx, params => spec.encodeResult(handler(ctx, spec.decodeParams(params)))
        }))
    }

    private func exclusive<P>(spec: LspInboundNotification<P>, handler: (Context, P) -> Unit): Router {
        add(notifications, spec.method, NotificationRoute.Exclusive({
            ctx, params => handler(ctx, spec.decodeParams(params))
        }))
    }

    /**
     * @throws IllegalArgumentException - if the method already has a handler, or is one of the
     * lifecycle's: whatever arrives after it must see the state it leaves
     */
    private func concurrent<P, R>(spec: LspInboundRequest<P, R>, handler: (ReadOnlyContext, P) -> R): Router {
        refuseLifecycle(spec.method)
        add(requests, spec.method, RequestRoute.ReadOnly({
            ctx, params => spec.encodeResult(handler(ctx, spec.decodeParams(params)))
        }))
    }

    private func concurrent<P>(spec: LspInboundNotification<P>, handler: (ReadOnlyContext, P) -> Unit): Router {
        refuseLifecycle(spec.method)
        add(notifications, spec.method, NotificationRoute.ReadOnly({
            ctx, params => handler(ctx, spec.decodeParams(params))
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
    | Exclusive((Context, ?ArrayOrObject) -> DataModel)
    | ReadOnly((ReadOnlyContext, ?ArrayOrObject) -> DataModel)
}

enum NotificationRoute {
    | Exclusive((Context, ?ArrayOrObject) -> Unit)
    | ReadOnly((ReadOnlyContext, ?ArrayOrObject) -> Unit)
}

private func refuseLifecycle(method: String): Unit {
    if (method == InitializeRequestSpec.METHOD || method == ShutdownRequestSpec.METHOD ||
        method == ExitNotificationSpec.METHOD) {
        throw IllegalArgumentException("\"${method}\" cannot be `readonly`")
    }
}
