package jsonrpc

import std.collection.concurrent.LinkedBlockingQueue
import stdx.serialization.serialization.*

public struct PendingRequest<R> where R <: Serializable<R> {
    /**
     * @param abandon - stops the connection correlating `id`
     */
    public PendingRequest(
        public let id: RequestId,
        private let slot: LinkedBlockingQueue<ResultOrError>,
        private let abandon: () -> Unit
    ) {}

    /**
     * Blocks the caller's own thread rather than a `spawn`ed one, so an error answer is a plain
     * throw rather than a worker's stack dumped to stderr.
     *
     * @throws RpcException - if the peer answered with an error
     * @throws DataModelException - if the result does not decode to an `R`
     */
    public func await(): R {
        decode(slot.remove())
    }

    /**
     * As `await`, but gives up after `timeout` and answers `None`. Giving up is final: a late
     * answer is dropped rather than parked for the lifetime of the connection.
     *
     * @throws RpcException - if the peer answered with an error
     * @throws DataModelException - if the result does not decode to an `R`
     */
    public func await(timeout!: Duration): ?R {
        if (let Some(resultOrError) <- slot.remove(timeout)) {
            return decode(resultOrError)
        }
        abandon()

        // the answer may have landed between the timeout and `abandon`; nothing can after it
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
