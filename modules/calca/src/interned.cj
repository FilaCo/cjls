package calca

import std.collection.*
import std.sync.*

/**
 * How many active revisions a value may go unused before it is collected, unless the type says.
 */
public const DEFAULT_REVISIONS: Int64 = 3

/**
 * A value of a `@CalcaInterned` type, which the generated struct implements: the interned table it
 * is in and its `Id` there. How a tracked function keyed by one learns to drop the memo of a value
 * once it is collected. Not for use by hand.
 */
public interface InternedValue {
    func calcaKey(): DatabaseKey
}

/**
 * A `@CalcaInterned` type, process-wide: where its table is in any database. Held by the static
 * `@CalcaInterned` generates; not for use by hand. `K` is the type's fields, as one value.
 *
 * `revisions` is how many active revisions of the table (ones it was used in at all) a value may
 * go unused before it is collected; `None` keeps every value as long as the database. Only values
 * interned inside a query, by queries that read nothing but `Low` inputs until then, are ever
 * collected (D18).
 *
 * A value that may be collected is not stable across revisions: its slot may be reused, under
 * another generation, by other fields. So interning it is recorded as a dependency of the query
 * interning, changed now; reading it records none, since whoever holds its `Id` got it from
 * interning or from a value that depends on interning.
 */
public class InternedIngredient<K> where K <: Hashable & Equatable<K> {
    let index: Int64

    /**
     * @throws IllegalArgumentException - if `revisions` is not positive
     */
    public InternedIngredient(let name: String, let revisions!: ?Int64 = DEFAULT_REVISIONS) {
        if (let Some(count) <- revisions) {
            if (count <= 0) {
                throw IllegalArgumentException("${name} keeps a value unused for at least one revision: ${count}")
            }
        }
        index = reserveIngredients(1)
    }

    /**
     * The `Id` of `fields`: the one they already have in this database, else a new one.
     */
    public func intern(db: Database, fields: K): Id {
        let storage = db.storage
        storage.read {
            let now = storage.runtime.revision
            let durability = storage.queryDurability
            let id = table(storage.runtime).intern(fields, durability, now)
            if (let (Some(_), Some(current)) <- (revisions, durability)) {
                // the query's own durability: `Low` would make every query that interns `Low`
                storage.reportRead(DatabaseKey(index, id), current, now)
            }
            id
        }
    }

    /**
     * The fields interned as `id`.
     *
     * @throws IllegalStateException - if `id` was collected
     */
    public func lookup(db: Database, id: Id): K {
        let storage = db.storage
        storage.read {
            table(storage.runtime).lookup(id, storage.runtime.revision)
        }
    }

    /**
     * What a value of the type answers to `InternedValue.calcaKey`.
     */
    public func key(id: Id): DatabaseKey {
        DatabaseKey(index, id)
    }

    /**
     * `Name(id)`, what the interned type's `toString` gives.
     */
    public func describe(id: Id): String {
        "${name}(${id})"
    }

    func table(runtime: Runtime): InternTable<K> {
        runtime.ingredient(index) {=> InternTable<K>(this)}
    }
}

/**
 * One value in an `InternTable`: its fields, the last revision it was used in, and the highest
 * durability a query interning it had then.
 */
class InternSlot<K> {
    InternSlot(let fields: K, var lastUsed: Int64, var durability: Durability) {}
}

/**
 * The ingredients that are told when values are collected: the memo tables keyed by the type.
 */
interface KeyedByInterned {
    /**
     * Drops what is keyed by `collected`. Called while nothing reads.
     */
    func dropKeys(collected: Array<Id>): Unit
}

/**
 * An `InternTable`, for a memo table keyed by its type to register with, not knowing `K`.
 */
interface InternedKeys {
    func watch(table: KeyedByInterned): Unit
}

/**
 * The values of one `@CalcaInterned` type in one database, in a `Slab`: a value's `Id` is its slot
 * and that slot's generation.
 */
class InternTable<K> <: Ingredient & InternedKeys where K <: Hashable & Equatable<K> {
    private let lock = Mutex()
    let values = Slab<InternSlot<K>>()
    private let ids = HashMap<K, Id>()

    /**
     * The `Low` values, least recently used first: the candidates for collection, which end at the
     * first one that is not stale rather than with a walk of the table.
     */
    private let lowValues = IdLru(Int64.Max)

    /**
     * The last `revisions` revisions the table was used in, oldest first. Each change of a file is a
     * revision of its own, so counting every revision would collect the names of one file while
     * another is typed in.
     */
    private let active = ArrayList<Int64>()

    private let watchers = ArrayList<KeyedByInterned>()

    InternTable(let ingredient: InternedIngredient<K>) {}

    /**
     * The `Id` of `fields`, interned by a query of `durability` so far, `None` outside any query.
     */
    func intern(fields: K, durability: ?Durability, now: Int64): Id {
        // outside a query, no memo depends on the value, and nothing would learn it is gone
        let atLeast = durability ?? Durability.High
        synchronized(lock) {
            match (ids.get(fields)) {
                case Some(id) =>
                    let slot = values.get(id).getOrThrow()
                    slot.durability = max(slot.durability, atLeast)
                    use(id, slot, now)
                    id
                case None =>
                    let slot = InternSlot(fields, now, atLeast)
                    let id = values.insert(slot)
                    ids.add(fields, id)
                    use(id, slot, now)
                    id
            }
        }
    }

    /**
     * @throws IllegalStateException - if `id` was collected
     */
    func lookup(id: Id, now: Int64): K {
        let slot = synchronized(lock) {
            let found = values.get(id)
            if (let Some(slot) <- found) {
                use(id, slot, now)
            }
            found
        }
        match (slot) {
            case Some(found) => found.fields
            case None => throw IllegalStateException("${ingredient.name} has no value ${id} in this database")
        }
    }

    /**
     * Called with the lock held.
     */
    private func use(id: Id, slot: InternSlot<K>, now: Int64): Unit {
        let revisions = match (ingredient.revisions) {
            case Some(count) => count
            case None => return
        }
        slot.lastUsed = now
        if (active.isEmpty() || active[active.size - 1] != now) {
            active.add(now)
            if (active.size > revisions) {
                active.remove(at: 0)
            }
        }
        if (slot.durability == Durability.Low) {
            lowValues.touch(Id(id.index))
        } else {
            lowValues.remove(Id(id.index))
        }
    }

    /**
     * Changed once the value was collected, its slot empty or someone else's. Otherwise it is used
     * now: a memo verified keeps alive what it interned, whether or not anything executes.
     */
    public func maybeChangedAfter(db: Database, id: Id, _: Int64): Bool {
        let now = db.storage.runtime.revision
        synchronized(lock) {
            match (values.get(id)) {
                case Some(slot) =>
                    use(id, slot, now)
                    false
                case None => true
            }
        }
    }

    /**
     * Collects the `Low` values not used in the last `revisions` active revisions, once there have
     * been that many, and tells the memo tables keyed by them.
     */
    public func newRevision(): Unit {
        let collected = synchronized(lock) {
            collect()
        }
        if (collected.isEmpty()) {
            return
        }
        let told = synchronized(lock) {
            watchers.toArray()
        }
        for (watcher in told) {
            watcher.dropKeys(collected)
        }
    }

    /**
     * Called with the lock held.
     */
    private func collect(): Array<Id> {
        let revisions = ingredient.revisions ?? return []
        if (active.size < revisions) {
            return []
        }
        let oldest = active[0]
        let collected = ArrayList<Id>()
        while (let Some(candidate) <- lowValues.oldestId) {
            let (id, slot) = values.getAt(candidate.index).getOrThrow()
            if (slot.lastUsed >= oldest) {
                break
            }
            lowValues.remove(candidate)
            ids.remove(slot.fields)
            values.remove(id)
            collected.add(id)
        }
        collected.toArray()
    }

    /**
     * Tells `table` from now on what is collected. Called once per table.
     */
    public func watch(table: KeyedByInterned): Unit {
        synchronized(lock) {
            watchers.add(table)
        }
    }

    public func describe(id: Id): String {
        ingredient.describe(id)
    }
}
