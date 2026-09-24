package jsonrpc

import stdx.serialization.serialization.*

/**
 * The framing itself is lost: there is no next message to find.
 */
public class TransportException <: Exception {
    public TransportException(msg: String) {
        super(msg)
    }

    protected override func getClassName() {
        "TransportException"
    }
}

/**
 * The message was bad but the stream is still in sync, so the peer can be answered with
 * `responseError` and reading can go on.
 */
public class RpcException <: Exception {
    public RpcException(public let responseError: ResponseError) {
        super(responseError.message)
    }

    public init(code: ErrorCode, message: String, data!: ?DataModel = None) {
        this(ResponseError(code, message, data: data))
    }

    public prop code: ErrorCode {
        get() {
            responseError.code
        }
    }

    public prop message: String {
        get() {
            responseError.message
        }
    }

    public prop data: ?DataModel {
        get() {
            responseError.data
        }
    }

    protected override func getClassName(): String {
        "RpcException"
    }
}
