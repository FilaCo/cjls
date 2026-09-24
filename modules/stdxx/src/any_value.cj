package stdxx

import stdx.serialization.serialization.*

/**
 * Any value at all, carried as the `DataModel`.
 *
 * `DataModel` cannot be `Serializable` itself: Cangjie forbids extending an imported type with an
 * imported interface, so it takes a type of our own to put one in a serializable field.
 *
 * `null` is one of the values it holds, not the absence of one.
 */
public struct AnyValue <: Serializable<AnyValue> {
    public AnyValue(public let data: DataModel) {}

    public static func deserialize(dm: DataModel): AnyValue {
        AnyValue(dm)
    }

    public func serialize(): DataModel {
        data
    }
}
