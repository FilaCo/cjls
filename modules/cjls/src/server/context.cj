package cjls.server

import stdx.log.Logger
import stdx.serialization.serialization.*
import jsonrpc.*

/**
 * What a handler that runs on the read loop gets besides its params - the `Database` itself among
 * them, since nothing else runs meanwhile.
 */
public class Context {
    Context(
        public let db: Database,
        public let client: Client,
        public let cancellation: CancellationToken,
        public let logger: Logger
    ) {}
}

/**
 * What a handler that runs on a thread of its own gets besides its params: a snapshot in place of
 * the database, so such a handler cannot change the inputs.
 */
public class ReadOnlyContext {
    ReadOnlyContext(
        public let db: DatabaseSnapshot,
        public let client: Client,
        public let cancellation: CancellationToken,
        public let logger: Logger
    ) {}
}

/**
 * A type a `@Handler` function can take before its params, the way axum's `FromRequestParts` is.
 */
public interface FromContext<T> {
    static func from(ctx: Context): T
}

/**
 * A type a `@Handler[readonly]` function can take before its params.
 */
public interface FromReadOnlyContext<T> {
    static func from(ctx: ReadOnlyContext): T
}

/**
 * Where the query database goes. It holds nothing yet, but is already split the way it will be: a
 * handler given a `Context` changes the database, one given a `ReadOnlyContext` reads a snapshot.
 */
public class Database <: FromContext<Database> {
    public init() {}

    public static func from(ctx: Context): Database {
        ctx.db
    }

    public func snapshot(): DatabaseSnapshot {
        DatabaseSnapshot()
    }
}

public class DatabaseSnapshot <: FromReadOnlyContext<DatabaseSnapshot> {
    public static func from(ctx: ReadOnlyContext): DatabaseSnapshot {
        ctx.db
    }
}

/**
 * Never cancelled for a notification.
 */
extend CancellationToken <: FromContext<CancellationToken> & FromReadOnlyContext<CancellationToken> {
    public static func from(ctx: Context): CancellationToken {
        ctx.cancellation
    }

    public static func from(ctx: ReadOnlyContext): CancellationToken {
        ctx.cancellation
    }
}

/**
 * Carries the method, and the id of a request, on every line it writes.
 */
extend Logger <: FromContext<Logger> & FromReadOnlyContext<Logger> {
    public static func from(ctx: Context): Logger {
        ctx.logger
    }

    public static func from(ctx: ReadOnlyContext): Logger {
        ctx.logger
    }
}

/**
 * The client, as the server talks to it. Bound to its connection once that exists: the connection
 * needs the server, and the server hands this out.
 */
public class Client <: FromContext<Client> & FromReadOnlyContext<Client> {
    private var connection: ?Connection = None

    public static func from(ctx: Context): Client {
        ctx.client
    }

    public static func from(ctx: ReadOnlyContext): Client {
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
     * @throws IllegalStateException - if the client is not connected yet
     * @throws RpcException - if params are not serialized to array|object|null
     * @throws TransportException - if the frame cannot be written
     */
    public func notify<P>(method: String, params: P): Unit where P <: Serializable<P> {
        connected().notify(method, params)
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
