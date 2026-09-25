package calca

import std.deriving.*

/**
 * What a value of an `@CalcaInput` type is: the row it occupies in its table in one database, and
 * meaningless in any other.
 */
@Derive[Equatable, Hashable]
public struct Id <: ToString {
    Id(let index: Int64) {}

    public func toString(): String {
        index.toString()
    }
}

/**
 * One value an ingredient holds: an input's field of one row, or a tracked function's memo for one
 * key. What a query reads is recorded as these.
 */
@Derive[Equatable, Hashable]
struct DatabaseKey {
    DatabaseKey(let ingredient: Int64, let id: Id) {}
}
