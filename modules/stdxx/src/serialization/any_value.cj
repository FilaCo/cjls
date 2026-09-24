package stdxx.serialization

import stdx.serialization.serialization.*

/**
 * Any value at all, `null` included, carried as its `DataModel`.
 *
 * `DataModel` cannot be `Serializable` itself: Cangjie forbids extending an imported type with an
 * imported interface, so a serializable field holding any value takes a type of our own.
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
