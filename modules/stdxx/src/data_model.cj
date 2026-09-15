package stdxx

import stdx.serialization.serialization.*

public interface DataModelShape {
    func asStructOrThrow(): DataModelStruct
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
     * presence-aware, unlike get(): None = key absent; Some(DataModelNull) = present & null. Last wins.
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
     * presence-aware, unlike get(): None = key absent; Some(T) = present & deserialized. Last wins.
     *
     * @throws DataModelException - if T.deserialize throws it.
     */
    public func getDeserializedOrNone<FieldT>(name: String): ?FieldT where FieldT <: Serializable<FieldT> {
        getOrNone(name).map {it => FieldT.deserialize(it)}
    }

    /**
     * `None` when the key is absent *or* explicitly `null` - for a plain optional field the two are
     * the same absence of a value. Use `getDeserializedOrNone` where `null` has to stay
     * distinguishable from absent, which is what `Nullable<T>` in the field type asks for.
     *
     * @throws DataModelException - if FieldT.deserialize throws it.
     */
    public func getDeserializedOrNoneOnNull<FieldT>(name: String): ?FieldT where FieldT <: Serializable<FieldT> {
        match (getOrNone(name)) {
            case Some(dm) => Option<FieldT>.deserialize(dm)
            case None => None
        }
    }

    /**
     * presence-aware, unlike get(), throws if key was not found (DataModelNull = present & null). Last wins.
     *
     * @throws DataModelException - if name is not found in the DataModelStruct.
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
