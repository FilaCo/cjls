package jsonrpc

import stdx.serialization.serialization.*
import stdxx.*

public struct ResponseError <: Serializable<ResponseError> {
    public ResponseError(
        /**
         * A number indicating the error type that occurred.
         */
        public let code: ErrorCode,
        /**
         * A string providing a short description of the error.
         */
        public let message: String,
        /**
         * A primitive or structured value that contains additional
         * information about the error. Can be omitted.
         */
        public let data!: ?DataModel = None) {}

    /**
     * @throws DataModelException - if not a `DataModelStruct` provided
     */
    public static func deserialize(dm: DataModel): ResponseError {
        if (let dms: DataModelStruct <- dm) {
            let data = dms.getOrNone("data")
            return ResponseError(ErrorCode.deserialize(dms.get("code")), String.deserialize(dms.get("message")),
                data: data)
        }

        throw DataModelException("expected `DataModelStruct`")
    }

    public func serialize(): DataModel {
        let dms = DataModelStruct()
        dms.add(field("code", code)).add(field("message", message))
        if (let Some(data) <- data) {
            dms.add(Field("data", data))
        }

        dms
    }
}

public struct ErrorCode <: Equatable<ErrorCode> & ToString & Serializable<ErrorCode> {
    public const ErrorCode(public let value: Int32) {}

    // Defined by JSON-RPC
    public static const PARSE_ERROR: ErrorCode = ErrorCode(-32700)
    public static const INVALID_REQUEST: ErrorCode = ErrorCode(-32600)
    public static const METHOD_NOT_FOUND: ErrorCode = ErrorCode(-32601)
    public static const INVALID_PARAMS: ErrorCode = ErrorCode(-32602)
    public static const INTERNAL_ERROR: ErrorCode = ErrorCode(-32603)

    /**
     * This is the start range of JSON-RPC reserved error codes.
     * It doesn't denote a real error code. No LSP error codes should
     * be defined between the start and end range. For backwards
     * compatibility the `ServerNotInitialized` and the `UnknownErrorCode`
     * are left in the range.
     *
     * @since 3.16.0
     */
    public static const JSONRPC_RESERVED_ERROR_RANGE_START: ErrorCode = ErrorCode(-32099)

    /**
     * Error code indicating that a server received a notification or
     * request before the server received the `initialize` request.
     */
    public static const SERVER_NOT_INITIALIZED: ErrorCode = ErrorCode(-32002)
    public static const UNKNOWN_ERROR_CODE: ErrorCode = ErrorCode(-32001)

    /**
     * This is the end range of JSON-RPC reserved error codes.
     * It doesn't denote a real error code.
     *
     * @since 3.16.0
     */
    public static const JSONRPC_RESERVED_ERROR_RANGE_END: ErrorCode = ErrorCode(-32000);

    public operator func ==(other: ErrorCode): Bool {
        value == other.value
    }

    public func toString(): String {
        value.toString()
    }

    /**
     * @throws DataModelException - if not a `DataModelInt` provided
     */
    public static func deserialize(dm: DataModel): ErrorCode {
        if (let dmi: DataModelInt <- dm) {
            let value = try {
                Int32(dmi.getValue())
            } catch (e: Exception) {
                throw DataModelException("invalid error code\nCause: ${e}")
            }
            return ErrorCode(value)
        }

        throw DataModelException("expected `DataModelInt`")
    }

    public func serialize(): DataModel {
        DataModelInt(Int64(value))
    }
}
