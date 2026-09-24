package jsonrpc

import std.sync.AtomicBool

/**
 * A peer request with the one right to answer it, from whichever thread. Only the first answer
 * goes out, so the connection's fallback for a handler that threw can never follow a real one.
 */
public class InboundRequest {
    private let answered = AtomicBool(false)

    /**
     * Public so a `Handler` can be driven without a connection behind it.
     *
     * @param deliver - must not throw: the thread answering may have nobody above it to catch
     */
    public InboundRequest(
        public let id: RequestId,
        public let method: String,
        public let params: ?ArrayOrObject,
        public let cancellation: CancellationToken,
        private let deliver: (ResultOrError) -> Unit
    ) {}

    public prop isAnswered: Bool {
        get() {
            answered.load()
        }
    }

    /**
     * Never throws: a connection closed in the meantime has nobody left to tell.
     *
     * @return whether this call was the one that answered
     */
    public func respond(resultOrError: ResultOrError): Bool {
        if (answered.swap(true)) {
            return false
        }
        deliver(resultOrError)
        true
    }

    /**
     * Responds with what `answer` gives, or with `responseErrorOf` what it throws - so nothing
     * escapes it, and it is a safe body for a `spawn`.
     */
    public func respondWith(answer: () -> ResultOrError): Bool {
        let resultOrError = try {
            answer()
        } catch (e: Exception) {
            ResultOrError.Error(responseErrorOf(e))
        }
        respond(resultOrError)
    }
}

/**
 * An `RpcException` answers with its own error, anything else with `INTERNAL_ERROR`.
 */
public func responseErrorOf(e: Exception): ResponseError {
    match (e) {
        case rpc: RpcException => rpc.responseError
        case _ => ResponseError(ErrorCode.INTERNAL_ERROR, e.message)
    }
}
