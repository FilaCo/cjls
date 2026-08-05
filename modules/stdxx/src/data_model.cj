package stdxx

import stdx.serialization.serialization.*

public interface DataModelFields {
    func getOrNone(name: String): ?DataModel
    func getDeserializedOrNone<T>(name: String): ?T where T <: Serializable<T>
    func getOrThrow(name: String): DataModel
    func getDeserializedOrThrow<T>(name: String): T where T <: Serializable<T>
    func addFieldIfSome<T>(name: String, v: ?T): Unit where T <: Serializable<T>
}

extend DataModelStruct <: DataModelFields {
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
    public func getDeserializedOrNone<T>(name: String): ?T where T <: Serializable<T> {
        getOrNone(name).map {it => T.deserialize(it)}
    }

    /**
     * presence-aware, unlike get(), throws if key was not found (DataModelNull = present & null). Last wins.
     *
     * @throws DataModelException - if name is not found in the DataModelStruct.
     */
    public func getOrThrow(name: String): DataModel {
        getOrNone(name).getOrThrow {=> DataModelException("required field \"${name}\" is absent")}
    }

    public func getDeserializedOrThrow<T>(name: String): T where T <: Serializable<T> {
        T.deserialize(getOrThrow(name))
    }

    public func addFieldIfSome<T>(name: String, v: ?T): Unit where T <: Serializable<T> {
        ifSome(v, {it => add(field(name, it))})
    }
}
