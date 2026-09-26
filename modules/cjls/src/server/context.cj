package cjls.server

import stdx.log.Logger
import stdx.serialization.serialization.*
import jsonrpc.*
import cjls.lsp_types.LspOutboundNotification

/**
 * What a handler that runs on the read loop gets: its params, and the `ServerState` itself, since
 * nothing else runs meanwhile.
 */
public class Context<P> {
    Context(
        public let params: P,
        public let state: ServerState,
        public let client: Client,
        public let cancellation: CancellationToken,
        public let logger: Logger
    ) {}
}

/**
 * What a handler that runs on a thread of its own gets: as `Context`, with a snapshot in place of
 * the state, so such a handler cannot change the inputs.
 */
public class ReadOnlyContext<P> {
    ReadOnlyContext(
        public let params: P,
        public let snapshot: ServerSnapshot,
        public let client: Client,
        public let cancellation: CancellationToken,
        public let logger: Logger
    ) {}
}

/**
 * A type a `@LspHandler` function can take before its params, the way axum's `FromRequestParts` is.
 */
public interface FromContext<T> {
    static func from<P>(ctx: Context<P>): T
}

/**
 * A type a `@LspHandler[readonly]` function can take before its params.
 */
public interface FromReadOnlyContext<T> {
    static func from<P>(ctx: ReadOnlyContext<P>): T
}

/**
 * A context but for its params, which the route decodes, knowing their type.
 */
class Parts {
    Parts(let state: ServerState, let client: Client, let cancellation: CancellationToken, let logger: Logger) {}

    func context<P>(params: P): Context<P> {
        Context(params, state, client, cancellation, logger)
    }
}

class ReadOnlyParts {
    ReadOnlyParts(let snapshot: ServerSnapshot, let client: Client, let cancellation: CancellationToken,
        let logger: Logger) {}

    func context<P>(params: P): ReadOnlyContext<P> {
        ReadOnlyContext(params, snapshot, client, cancellation, logger)
    }
}

/**
 * Never cancelled for a notification.
 */
extend CancellationToken <: FromContext<CancellationToken> & FromReadOnlyContext<CancellationToken> {
    public static func from<P>(ctx: Context<P>): CancellationToken {
        ctx.cancellation
    }

    public static func from<P>(ctx: ReadOnlyContext<P>): CancellationToken {
        ctx.cancellation
    }
}

/**
 * Carries the method, and the id of a request, on every line it writes.
 */
extend Logger <: FromContext<Logger> & FromReadOnlyContext<Logger> {
    public static func from<P>(ctx: Context<P>): Logger {
        ctx.logger
    }

    public static func from<P>(ctx: ReadOnlyContext<P>): Logger {
        ctx.logger
    }
}

/**
 * The client, as the server talks to it. Bound to its connection once that exists: the connection
 * needs the server, and the server hands this out.
 */
public class Client <: FromContext<Client> & FromReadOnlyContext<Client> {
    private var connection: ?Connection = None

    public static func from<P>(ctx: Context<P>): Client {
        ctx.client
    }

    public static func from<P>(ctx: ReadOnlyContext<P>): Client {
        ctx.client
    }

    /**
     * @throws IllegalStateException - if the client is already connected
     */
    func connect(connection: Connection): Unit {
        if (this.connection.isSome()) {
            throw IllegalStateException("the client is already connected")
        }
        this.connection = connection
    }

    /**
     * Sends the notification `spec` names, as `route` takes the ones the client sends: the method
     * and the type of the params come with it.
     *
     * @throws IllegalStateException - if the client is not connected yet
     * @throws RpcException - if params are not serialized to array|object|null
     * @throws TransportException - if the frame cannot be written
     */
    public func notify<P>(spec: LspOutboundNotification<P>, params: P): Unit where P <: Serializable<P> {
        connected().notify(spec.method, params)
    }

    /**
     * @note never await the answer from a handler given a `Context`: it can only arrive through the
     * read loop that handler is holding
     *
     * @throws IllegalStateException - if the client is not connected yet
     * @throws RpcException - if params are not serialized to array|object|null
     * @throws TransportException - if the frame cannot be written
     */
    public func request<P, R>(method: String, params: P): PendingRequest<R> where P <: Serializable<P>,
        R <: Serializable<R> {
        connected().request<P, R>(method, params)
    }

    /**
     * Tells the handler of an inbound request to give up.
     */
    public func cancel(id: RequestId): Unit {
        connection?.cancel(id)
    }

    public func close(): Unit {
        connection?.close()
    }

    private func connected(): Connection {
        connection.getOrThrow {=> IllegalStateException("the client is not connected yet")}
    }
}
