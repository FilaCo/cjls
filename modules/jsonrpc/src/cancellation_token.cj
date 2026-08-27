package jsonrpc

import std.sync.AtomicBool

public class CancellationToken {
    private let flag = AtomicBool(false)

    public prop isCancelled: Bool {
        get() {
            flag.load()
        }
    }

    public func cancel(): Unit {
        flag.store(true)
    }

    /**
     * @throws RpcException - if cancelled
     */
    public func throwIfCancelled(): Unit {
        if (isCancelled) {
            throw RpcException(ErrorCode.INTERNAL_ERROR, "cancelled")
        }
    }
}
