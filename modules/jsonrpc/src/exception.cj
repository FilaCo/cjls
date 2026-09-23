package jsonrpc

import stdx.serialization.serialization.*

/**
 * The framing itself is lost - the stream is desynced and there is no next message to find.
 */
public class TransportException <: Exception {
    public TransportException(msg: String) {
        super(msg)
    }

    protected override func getClassName() {
        "TransportException"
    }
}

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
