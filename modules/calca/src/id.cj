package calca

import std.deriving.*

const INDEX_BITS: UInt64 = 0xFFFF_FFFF

/**
 * What a value of an `@CalcaInput` type is: the row it occupies in its table in one database, and
 * meaningless in any other.
 *
 * A slot collected and reused holds another value under the same index, so an `Id` also carries the
 * generation of its slot: 32 bits of each in one word, so neither `Id` nor `DatabaseKey` grows. What
 * never reuses a slot (an input's row) is always of generation 0.
 */
@Derive[Equatable, Hashable]
public struct Id <: ToString {
    let bits: UInt64

    /**
     * @throws IllegalArgumentException - if `index` does not fit in 32 bits
     */
    Id(index: Int64, generation!: UInt32 = 0) {
        if (index < 0 || index > Int64(INDEX_BITS)) {
            throw IllegalArgumentException("an index fits in 32 bits: ${index}")
        }
        bits = (UInt64(generation) << 32) | UInt64(index)
    }

    prop index: Int64 {
        get() {
            Int64(bits & INDEX_BITS)
        }
    }

    prop generation: UInt32 {
        get() {
            UInt32(bits >> 32)
        }
    }

    /**
     * The index, and the generation after a `g` once there is one: `3`, `3g1`.
     */
    public func toString(): String {
        if (generation == 0) {
            index.toString()
        } else {
            "${index}g${generation}"
        }
    }
}

/**
 * One value an ingredient holds: an input's field of one row, a tracked function's memo for one
 * key, an interned value. What a query reads is recorded as these. Public only for
 * `InternedValue.calcaKey`, which generated code implements.
 */
@Derive[Equatable, Hashable]
public struct DatabaseKey {
    DatabaseKey(let ingredient: Int64, let id: Id) {}
}
