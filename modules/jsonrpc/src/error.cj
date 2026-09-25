package jsonrpc

import std.deriving.*
import stdx.serialization.serialization.*
import stdxx.serialization.*

public struct ResponseError <: Serializable<ResponseError> {
    public ResponseError(public let code: ErrorCode, public let message: String, public let data!: ?DataModel = None) {}

    /**
     * @throws DataModelException - if not a `DataModelStruct` provided
     */
    public static func deserialize(dm: DataModel): ResponseError {
        let dms = dm.asStructOrThrow()

        ResponseError(dms.getDeserializedOrThrow("code"), dms.getDeserializedOrThrow("message"),
            data: dms.getOrNone("data"))
    }

    public func serialize(): DataModel {
        DataModelStruct().add(field("code", code)).add(field("message", message)).addFieldIfSome("data", data)
    }
}

/**
 * Open rather than an enum, so a code this side does not know survives a round trip.
 */
@Derive[Equatable]
public struct ErrorCode <: ToString & Serializable<ErrorCode> {
    public const ErrorCode(public let value: Int32) {}

    public static const PARSE_ERROR: ErrorCode = ErrorCode(-32700)
    public static const INVALID_REQUEST: ErrorCode = ErrorCode(-32600)
    public static const METHOD_NOT_FOUND: ErrorCode = ErrorCode(-32601)
    public static const INVALID_PARAMS: ErrorCode = ErrorCode(-32602)
    public static const INTERNAL_ERROR: ErrorCode = ErrorCode(-32603)

    public func toString(): String {
        value.toString()
    }

    /**
     * @throws DataModelException - if not a `DataModelInt` provided
     */
    public static func deserialize(dm: DataModel): ErrorCode {
        let raw = dm.asIntOrThrow()
        let value = try {
            Int32(raw)
        } catch (e: OverflowException) {
            throw DataModelException("invalid error code\nCause: ${e}")
        }

        ErrorCode(value)
    }

    public func serialize(): DataModel {
        DataModelInt(Int64(value))
    }
}
