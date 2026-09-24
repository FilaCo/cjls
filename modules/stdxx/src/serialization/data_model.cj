package stdxx.serialization

import stdx.serialization.serialization.*

// Interfaces rather than bare `extend`s: Cangjie exports a direct extension only to its own package.

public interface DataModelShape {
    func asStructOrThrow(): DataModelStruct
    func asSeqOrThrow(): DataModelSeq
    func asStringOrThrow(): String
    func asIntOrThrow(): Int64
    func asBoolOrThrow(): Bool
}

public interface DataModelFields<SelfT> {
    func getOrNone(name: String): ?DataModel
    func getDeserializedOrNone<FieldT>(name: String): ?FieldT where FieldT <: Serializable<FieldT>
    func getDeserializedOrNoneOnNull<FieldT>(name: String): ?FieldT where FieldT <: Serializable<FieldT>
    func getOrThrow(name: String): DataModel
    func getDeserializedOrThrow<FieldT>(name: String): FieldT where FieldT <: Serializable<FieldT>
    func addFieldIfSome<FieldT>(name: String, v: ?FieldT): SelfT where FieldT <: Serializable<FieldT>
    func addFieldIfSome(name: String, v: ?DataModel): SelfT
}

extend DataModel <: DataModelShape {
    public func asStructOrThrow(): DataModelStruct {
        match (this) {
            case dms: DataModelStruct => dms
            case _ => throw DataModelException("expected `DataModelStruct`")
        }
    }

    public func asSeqOrThrow(): DataModelSeq {
        match (this) {
            case dmSeq: DataModelSeq => dmSeq
            case _ => throw DataModelException("expected `DataModelSeq`")
        }
    }

    public func asStringOrThrow(): String {
        match (this) {
            case dmStr: DataModelString => dmStr.getValue()
            case _ => throw DataModelException("expected `DataModelString`")
        }
    }

    public func asIntOrThrow(): Int64 {
        match (this) {
            case dmInt: DataModelInt => dmInt.getValue()
            case _ => throw DataModelException("expected `DataModelInt`")
        }
    }

    public func asBoolOrThrow(): Bool {
        match (this) {
            case dmBool: DataModelBool => dmBool.getValue()
            case _ => throw DataModelException("expected `DataModelBool`")
        }
    }
}

extend DataModelStruct <: DataModelFields<DataModelStruct> {
    /**
     * Unlike `get`, which reads an absent key as `DataModelNull`, tells absent (`None`) from an
     * explicit `null` (`Some(DataModelNull)`). A repeated key reads as its last value.
     */
    public func getOrNone(name: String): ?DataModel {
        getFields().filterMap {
            field: Field => if (field.getName() == name) {
                Some(field.getData())
            } else {
                None<DataModel>
            }
        }.last
    }

    /**
     * `None` only for an absent key: an explicit `null` goes to `FieldT`, where a `Nullable` keeps it.
     */
    public func getDeserializedOrNone<FieldT>(name: String): ?FieldT where FieldT <: Serializable<FieldT> {
        getOrNone(name).map {it => FieldT.deserialize(it)}
    }

    /**
     * `None` for an absent key and for an explicit `null` alike - to a plain optional they mean the same.
     */
    public func getDeserializedOrNoneOnNull<FieldT>(name: String): ?FieldT where FieldT <: Serializable<FieldT> {
        match (getOrNone(name)) {
            case Some(dm) => Option<FieldT>.deserialize(dm)
            case None => None
        }
    }

    /**
     * @throws DataModelException - if the key is absent; an explicit `null` is present
     */
    public func getOrThrow(name: String): DataModel {
        getOrNone(name).getOrThrow {=> DataModelException("required field \"${name}\" is absent")}
    }

    public func getDeserializedOrThrow<FieldT>(name: String): FieldT where FieldT <: Serializable<FieldT> {
        FieldT.deserialize(getOrThrow(name))
    }

    public func addFieldIfSome<FieldT>(name: String, v: ?FieldT): DataModelStruct where FieldT <: Serializable<FieldT> {
        ifSome(v, {it => add(field(name, it))})
        this
    }

    public func addFieldIfSome(name: String, v: ?DataModel): DataModelStruct {
        ifSome(v, {it => add(Field(name, it))})
        this
    }
}
