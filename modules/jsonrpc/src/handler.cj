package jsonrpc


/**
 * Both callbacks run on the read loop, one at a time, in arrival order, and nothing further
 * is read until a callback returns. Slow work belongs on a thread of the handler's own: for a
 * request, carry the `InboundRequest` there and answer from it.
 *
 * @note never wait on an outbound `PendingRequest` from inside a callback: its answer can only
 * arrive through the read loop the callback is holding up.
 */
public interface Handler {
    /**
     * The handler owes the request one answer, now or later. A throw before it answered is
     * answered for it, as `responseErrorOf` maps it.
     */
    func onRequest(request: InboundRequest): Unit

    func onNotification(method: String, params: ?ArrayOrObject): Unit
}
