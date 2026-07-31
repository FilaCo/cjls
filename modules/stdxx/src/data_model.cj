package stdxx

import stdx.serialization.serialization.*

public interface DataModelFields {
    func getOrNone(name: String): ?DataModel
}

extend DataModelStruct <: DataModelFields {
    // presence-aware, unlike get(): None = key absent; Some(DataModelNull) = present & null. Last wins.
    public func getOrNone(name: String): ?DataModel {
        getFields().filterMap {
            field: Field => if (field.getName() == name) {
                Some(field.getData())
            } else {
                None<DataModel>
            }
        }.last
    }
}
