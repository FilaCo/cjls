package jsonrpc

import stdx.serialization.serialization.*
import stdxx.UnexpectedVariantException

/**
 * The params of a request or a notification: JSON-RPC allows only a structured value there.
 */
public enum ArrayOrObject <: Serializable<ArrayOrObject> {
    | Array(DataModelSeq)
    | Object(DataModelStruct)

    /**
     * @throws DataModelException - if not a DataModelSeq or DataModelStruct
     */
    public static func deserialize(dm: DataModel): ArrayOrObject {
        match (dm) {
            case dms: DataModelSeq => Array(dms)
            case dms: DataModelStruct => Object(dms)
            case _ => throw DataModelException("expected `DataModelSeq` or `DataModelStruct`")
        }
    }

    public func serialize(): DataModel {
        match (this) {
            case Array(dms) => dms
            case Object(dms) => dms
        }
    }

    /**
     * @throws UnexpectedVariantException - if it holds an `Object`
     */
    public func getArrayOrThrow(): DataModelSeq {
        match (this) {
            case Array(arr) => arr
            case Object(_) => throw UnexpectedVariantException("Array", "Object")
        }
    }

    /**
     * @throws UnexpectedVariantException - if it holds an `Array`
     */
    public func getObjectOrThrow(): DataModelStruct {
        match (this) {
            case Object(obj) => obj
            case Array(_) => throw UnexpectedVariantException("Object", "Array")
        }
    }
}
