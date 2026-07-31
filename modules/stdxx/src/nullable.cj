package stdxx

import stdx.serialization.serialization.*

public enum Nullable<T> {
    | Value(T)
    | Null

    public func isValue(): Bool {
        match (this) {
            case Value(_) => true
            case Null => false
        }
    }

    public func isNull(): Bool {
        !isValue()
    }

    /**
     * @throws NullValueException - if it holds `Null`
     */
    public func getOrThrow(): T {
        match (this) {
            case Value(v) => v
            case Null => throw NullValueException()
        }
    }
}

extend<T> Nullable<T> <: Serializable<Nullable<T>> where T <: Serializable<T> {
    public static func deserialize(dm: DataModel): Nullable<T> {
        if (dm is DataModelNull) {
            return Null
        }

        Value(T.deserialize(dm))
    }

    public func serialize(): DataModel {
        match (this) {
            case Value(s) => s.serialize()
            case Null => DataModelNull()
        }
    }
}
