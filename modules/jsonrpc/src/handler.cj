package jsonrpc

import stdx.serialization.serialization.*
import stdxx.*

public interface Handler {
    /**
     * Answers a peer request. Failure is a return value, not an exception: an
     * unroutable method is an ordinary outcome for a router, not something worth
     * unwinding a stack over.
     *
     * @note throwing is still honoured for handlers that bail out deep in a call
     * chain - an `RpcException` becomes that error, and any other exception becomes
     * an `INTERNAL_ERROR`.
     */
    func onRequest(method: String, params: ?ArrayOrObject, cancel: CancellationToken): ResultOrError
    func onNotification(method: String, params: ?ArrayOrObject): Unit
}
