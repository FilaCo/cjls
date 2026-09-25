package calca

import std.collection.*
import std.sync.*
import index_map.*

/**
 * A `@CalcaTracked` function, process-wide: where its memos are in any database. Held by the static
 * `@CalcaTracked` generates; not for use by hand.
 *
 * The body comes with every `fetch` rather than here: a static whose initializer reaches the body
 * does not compile once tracked functions call each other, since cjc then sees the static used
 * before it is initialized.
 *
 * `equal` tells whether a value computed again is the one remembered, in which case the memo keeps
 * the revision it last changed in and what read it need not run again ("backdating").
 */
public class TrackedFunction<D, K, V> where D <: Database, K <: Hashable & Equatable<K> {
    let index: Int64

    public TrackedFunction(let name: String, let equal: (V, V) -> Bool) {
        index = reserveIngredients(1)
    }

    /**
     * The value of the function at `key`: remembered, if nothing it read has changed since, else
     * computed again. Recorded as read by the query running.
     *
     * @throws Cancelled - if a write is pending, or `db` is a snapshot of a revision gone by
     * @throws CycleException - if the value is already being computed on this handle
     */
    public func fetch(db: D, key: K, execute: (D, K) -> V): V {
        let storage = db.storage
        storage.read {
            let memos = storage.runtime.ingredient(index) {=> MemoTable(this, execute)}
            let id = memos.intern(key)
            let memo = memos.fetchMemo(db, storage, id, key)
            storage.reportRead(DatabaseKey(index, id), memo.durability, memo.changedAt)
            memo.value
        }
    }
}

/**
 * A value computed, with what it was computed from.
 */
class Memo<V> {
    /**
     * The last revision this value is known to be current in.
     */
    let verifiedAt: AtomicInt64

    Memo(
        verifiedAt: Int64,
        let value: V,
        let changedAt: Int64,
        let durability: Durability,
        let dependencies: Array<DatabaseKey>
    ) {
        this.verifiedAt = AtomicInt64(verifiedAt)
    }
}

/**
 * The memos of one tracked function in one database, one per key it was called with. A key's `Id` is
 * its index, given the first time it is seen, so what depends on it can name it.
 */
class MemoTable<D, K, V> <: Ingredient where D <: Database, K <: Hashable & Equatable<K> {
    private let lock = Mutex()
    private let entries = IndexMap<K, ?Memo<V>>()

    /**
     * The function itself, the same whichever `fetch` gave it.
     */
    MemoTable(let function: TrackedFunction<D, K, V>, let body: (D, K) -> V) {}

    func intern(key: K): Id {
        synchronized(lock) {
            // not `addWithIndex` alone: it would replace the memo of a key already there
            Id(entries.indexOf(key) ?? entries.addWithIndex(key, None)[0])
        }
    }

    /**
     * The memo at `id`, verified or computed again.
     */
    func fetchMemo(db: D, storage: Storage, id: Id, key: K): Memo<V> {
        let databaseKey = DatabaseKey(function.index, id)
        storage.enter(databaseKey)
        try {
            let old = synchronized(lock) {
                entry(id)[1]
            }
            match (old) {
                case Some(memo) where verify(db, storage.runtime, memo) => memo
                case _ => execute(db, storage, databaseKey, key, old)
            }
        } finally {
            storage.exit(databaseKey)
        }
    }

    /**
     * Whether `memo` is current, marking it so if it is. Cheap when no input it could have read
     * changed since it was last verified; otherwise asks each of its dependencies in turn, which
     * may verify or execute those.
     */
    private func verify(db: D, runtime: Runtime, memo: Memo<V>): Bool {
        let now = runtime.revision
        let verifiedAt = memo.verifiedAt.load()
        if (verifiedAt == now) {
            return true
        }
        let changed = runtime.lastChangedAt(memo.durability) > verifiedAt && memo.dependencies.iterator().any {
            dependency => runtime.ingredientAt(dependency.ingredient).maybeChangedAfter(db, dependency.id, verifiedAt)
        }
        if (changed) {
            return false
        }
        memo.verifiedAt.store(now)
        true
    }

    private func execute(db: D, storage: Storage, databaseKey: DatabaseKey, key: K, old: ?Memo<V>): Memo<V> {
        let frame = storage.push(databaseKey)
        let value = try {
            body(db, key)
        } finally {
            storage.pop()
        }
        let changedAt = match (old) {
            case Some(memo) where frame.durability >= memo.durability && (function.equal)(memo.value, value) =>
                memo.changedAt
            case _ => frame.changedAt
        }
        let memo = Memo(storage.runtime.revision, value, changedAt, frame.durability, frame.dependencies.toArray())
        synchronized(lock) {
            entries.add(key, memo)
        }
        memo
    }

    public func maybeChangedAfter(db: Database, id: Id, revision: Int64): Bool {
        let typed = (db as D).getOrThrow {=> IllegalStateException("${function.name} is given a database of another type")}
        let key = synchronized(lock) {
            entry(id)[0]
        }
        fetchMemo(typed, db.storage, id, key).changedAt > revision
    }

    public func describe(id: Id): String {
        "${function.name}(${id})"
    }

    /**
     * Called with the lock held.
     */
    private func entry(id: Id): (K, ?Memo<V>) {
        entries.getAt(id.index).getOrThrow {=> IllegalStateException("${function.name} has no key ${id}")}
    }
}
