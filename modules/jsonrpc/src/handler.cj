package jsonrpc


/**
 * What the connection hands inbound messages to. Both callbacks run on the read
 * loop, one at a time, in the order the messages arrived - so a handler sees
 * `didChange` after the `didOpen` before it without doing anything for it, and
 * nothing further is read until a callback returns. Work that may take a while
 * belongs on a thread of the handler's own: for a request, carry the
 * `InboundRequest` there and answer from it.
 *
 * @note never wait on an outbound `PendingRequest` from inside a callback: its
 * answer can only arrive through the read loop the callback is holding up.
 */
public interface Handler {
    /**
     * Takes a peer request. The handler owes it exactly one `respond`, now or
     * later; an unroutable method is an ordinary answer, not a throw.
     *
     * @note throwing is still honoured for a handler that bails out before it
     * answered - an `RpcException` becomes that error, and any other exception an
     * `INTERNAL_ERROR`. A throw after the request was answered changes nothing.
     */
    func onRequest(request: InboundRequest): Unit

    func onNotification(method: String, params: ?ArrayOrObject): Unit
}
