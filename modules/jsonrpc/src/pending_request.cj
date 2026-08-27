package jsonrpc

import std.collection.concurrent.LinkedBlockingQueue
import stdx.serialization.serialization.*

public struct PendingRequest<R> where R <: Serializable<R> {
    /**
     * @param abandon - unregisters the id with the connection, so that a response
     * arriving after the caller gave up is dropped instead of parked forever
     */
    public PendingRequest(
        public let id: RequestId,
        private let slot: LinkedBlockingQueue<ResultOrError>,
        private let abandon: () -> Unit
    ) {}

    /**
     * Blocks the calling thread until the peer answers. Deliberately not wrapped in
     * a `spawn`: the caller's own thread waits, so a rejected request surfaces as a
     * plain throw instead of the runtime dumping the stack of a doomed worker.
     *
     * @throws RpcException - if the peer answered with an error
     * @throws DataModelException - if the result does not decode to an `R`
     */
    public func await(): R {
        decode(slot.remove())
    }

    /**
     * As `await`, but gives up after `timeout` and answers `None`. Giving up is
     * final - the id stops being correlated, so a peer that answers late is ignored
     * rather than left holding a slot for the lifetime of the connection.
     *
     * @throws RpcException - if the peer answered with an error
     * @throws DataModelException - if the result does not decode to an `R`
     */
    public func await(timeout!: Duration): ?R {
        if (let Some(resultOrError) <- slot.remove(timeout)) {
            return decode(resultOrError)
        }
        abandon()

        // the answer may have landed in the gap between the timeout expiring and the
        // id being dropped; nothing can reach the slot after `abandon`, so a single
        // non-blocking look settles it
        slot.tryRemove().map {resultOrError => decode(resultOrError)}
    }

    /**
     * @throws RpcException - if the peer answered with an error
     * @throws DataModelException - if the result does not decode to an `R`
     */
    private func decode(resultOrError: ResultOrError): R {
        match (resultOrError) {
            case Result(dm) => R.deserialize(dm)
            case Error(err) => throw RpcException(err)
        }
    }
}
