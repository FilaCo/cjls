package calca

import std.sync.*
import index_map.*

/**
 * A `@CalcaInterned` type, process-wide: where its table is in any database. Held by the static
 * `@CalcaInterned` generates; not for use by hand. `K` is the type's fields, as one value.
 *
 * An interned value lives as long as its database, so neither interning nor reading one is recorded
 * as a dependency: no revision can change what an `Id` stands for.
 */
public class InternedIngredient<K> where K <: Hashable & Equatable<K> {
    private let index: Int64

    public InternedIngredient(let name: String) {
        index = reserveIngredients(1)
    }

    /**
     * The `Id` of `fields`: the one they already have in this database, else a new one.
     */
    public func intern(db: Database, fields: K): Id {
        let storage = db.storage
        storage.ensureOpen()
        table(storage.runtime).intern(fields)
    }

    /**
     * The fields interned as `id`.
     */
    public func lookup(db: Database, id: Id): K {
        table(db.storage.runtime).lookup(id)
    }

    /**
     * `Name(id)`, what the interned type's `toString` gives.
     */
    public func describe(id: Id): String {
        "${name}(${id})"
    }

    private func table(runtime: Runtime): InternTable<K> {
        runtime.ingredient(index) {=> InternTable<K>(this)}
    }
}

/**
 * The values of one `@CalcaInterned` type in one database. A value's `Id` is its index.
 */
class InternTable<K> <: Ingredient where K <: Hashable & Equatable<K> {
    private let lock = Mutex()
    private let values = IndexMap<K, Unit>()

    InternTable(let ingredient: InternedIngredient<K>) {}

    func intern(fields: K): Id {
        synchronized(lock) {
            match (values.indexOf(fields)) {
                case Some(index) => Id(index)
                case None => Id(values.addWithIndex(fields, ())[0])
            }
        }
    }

    func lookup(id: Id): K {
        let entry = synchronized(lock) {
            values.getAt(id.index)
        }
        match (entry) {
            case Some((fields, _)) => fields
            case None => throw IllegalStateException("${ingredient.name} has no value ${id} in this database")
        }
    }

    public func maybeChangedAfter(_: Database, _: Id, _: Int64): Bool {
        false
    }

    public func describe(id: Id): String {
        ingredient.describe(id)
    }
}
