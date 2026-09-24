package cjls.server

import stdx.serialization.serialization.*
import jsonrpc.*

/**
 * Where the query database goes. Until it exists this holds nothing, but the split is already the
 * one it will have: a handler registered with `route` changes the database, a `readonly` one reads
 * a snapshot of it.
 */
public class Database {
    public init() {}

    /**
     * Taken on the read loop when a message arrives, so it reflects every change before that
     * message and none after it.
     */
    public func snapshot(): DatabaseSnapshot {
        DatabaseSnapshot()
    }
}

public class DatabaseSnapshot {}

/**
 * The client, as the server talks to it: notifications and requests of our own. Bound to its
 * connection once that exists - the connection needs the router, and the router hands this out.
 */
public class Client {
    private var connection: ?Connection = None

    /**
     * @throws IllegalStateException - if the client is already connected
     */
    public func connect(connection: Connection): Unit {
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
     * @note never await the answer from a handler registered with `route`: it can only arrive
     * through the read loop that handler is holding
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
     * Tells the handler of an inbound request to give up - what `$/cancelRequest` asks for.
     */
    public func cancel(id: RequestId): Unit {
        connection?.cancel(id)
    }

    /**
     * Ends the connection, and with it the read loop. A client never connected has none to end.
     */
    public func close(): Unit {
        connection?.close()
    }

    private func connected(): Connection {
        connection.getOrThrow {=> IllegalStateException("the client is not connected yet")}
    }
}

/**
 * What a handler registered with `route` gets: the message's params, and the server around it -
 * the `Database` to itself, since such a handler runs on the read loop, alone.
 */
public class Context<P> {
    Context(
        public let params: P,
        public let db: Database,
        public let client: Client,
        /**
         * Whether the client still wants the answer; never cancelled for a notification.
         */
        public let cancellation: CancellationToken
    ) {}
}

/**
 * What a `readonly` handler gets: as `Context`, with a snapshot in place of the database, so such a
 * handler cannot change the inputs.
 */
public class ReadOnlyContext<P> {
    ReadOnlyContext(
        public let params: P,
        public let db: DatabaseSnapshot,
        public let client: Client,
        /**
         * Whether the client still wants the answer; never cancelled for a notification.
         */
        public let cancellation: CancellationToken
    ) {}
}

/**
 * The part of a `Context` the router has before the params are decoded - the routes decode them,
 * knowing their type.
 */
class Scope {
    Scope(let db: Database, let client: Client, let cancellation: CancellationToken) {}

    func context<P>(params: P): Context<P> {
        Context(params, db, client, cancellation)
    }
}

class ReadOnlyScope {
    ReadOnlyScope(let db: DatabaseSnapshot, let client: Client, let cancellation: CancellationToken) {}

    func context<P>(params: P): ReadOnlyContext<P> {
        ReadOnlyContext(params, db, client, cancellation)
    }
}
