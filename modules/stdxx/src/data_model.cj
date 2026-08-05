package stdxx

import stdx.serialization.serialization.*

public interface DataModelFields {
    func getOrNone(name: String): ?DataModel
    func getOrThrow(name: String): DataModel
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
     * presence-aware, unlike get(), throws if key is not found (DataModelNull is ok). Last wins.
     * @throws DataModelException - if name is not found in the DataModelStruct.
     */
    public func getOrThrow(name: String): DataModel {
        getOrNone(name).getOrThrow {=> DataModelException("required field \"${name}\" is absent")}
    }
}
