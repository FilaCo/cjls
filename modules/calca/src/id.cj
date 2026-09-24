package calca

/**
 * What a value of an `@Input` type is: the row it occupies in its table in one database, and
 * meaningless in any other.
 */
public struct Id <: Hashable & Equatable<Id> & ToString {
    Id(let index: Int64) {}

    public func hashCode(): Int64 {
        index.hashCode()
    }

    public operator func ==(other: Id): Bool {
        index == other.index
    }

    public operator func !=(other: Id): Bool {
        index != other.index
    }

    public func toString(): String {
        index.toString()
    }
}

/**
 * One value an ingredient holds: an input's field of one row, or a tracked function's memo for one
 * key. What a query reads is recorded as these.
 */
struct DatabaseKey <: Hashable & Equatable<DatabaseKey> {
    DatabaseKey(let ingredient: Int64, let id: Id) {}

    public func hashCode(): Int64 {
        var hasher = DefaultHasher()
        hasher.write(ingredient)
        hasher.write(id.index)
        hasher.finish()
    }

    public operator func ==(other: DatabaseKey): Bool {
        ingredient == other.ingredient && id == other.id
    }

    public operator func !=(other: DatabaseKey): Bool {
        !(this == other)
    }
}
