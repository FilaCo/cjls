package calca

import std.collection.*
import std.sync.*

/**
 * An `@Input` type, process-wide: where its table and its columns are in any database. Held by the
 * static `@Input` generates; not for use by hand.
 */
public class InputIngredient {
    private let base: Int64

    public InputIngredient(let name: String, let fields: Array<String>) {
        base = reserveIngredients(1 + fields.size)
    }

    /**
     * Adds a row, which `fill` gives a value in every column, in order.
     */
    public func create(db: Database, durability: Durability, fill: (InputRow) -> Unit): Id {
        let storage = db.storage
        storage.ensureOpen()
        let table = table(storage.runtime)
        synchronized(table.lock) {
            let id = Id(table.rows)
            fill(InputRow(this, storage.runtime, id, durability))
            table.rows++
            id
        }
    }

    /**
     * The value of `field` at `id`, recorded as read by the query running.
     */
    public func get<T>(db: Database, field: Int64, id: Id): T {
        let storage = db.storage
        storage.unwindIfCancelled()
        column<T>(storage.runtime, field).get(storage, id)
    }

    public func set<T>(db: Database, field: Int64, id: Id): Setter<T> {
        let storage = db.storage
        Setter(column<T>(storage.runtime, field), storage, id)
    }

    /**
     * `Name(id)`, what the input's `toString` gives.
     */
    public func describe(id: Id): String {
        "${name}(${id})"
    }

    func table(runtime: Runtime): InputTable {
        runtime.ingredient(base) {=> InputTable(name)}
    }

    func column<T>(runtime: Runtime, field: Int64): InputColumn<T> {
        let table = table(runtime)
        runtime.ingredient(base + 1 + field) {=> InputColumn<T>(table, base + 1 + field, fields[field])}
    }
}

/**
 * The row `InputIngredient.create` is adding.
 */
public class InputRow {
    InputRow(private let ingredient: InputIngredient, private let runtime: Runtime, private let id: Id,
        private let durability: Durability) {}

    public func put<T>(field: Int64, value: T): Unit {
        ingredient.column<T>(runtime, field).push(id, Stamp(value, runtime.revision, durability))
    }
}

/**
 * Changes one field of one input, in a revision of its own:
 *
 * ```cangjie
 * file.setText(db).to(text)
 * file.setText(db).withDurability(Durability.High).to(text)
 * ```
 */
public class Setter<T> {
    private var durability: ?Durability = None

    Setter(private let column: InputColumn<T>, private let storage: Storage, private let id: Id) {}

    /**
     * Keeps the field's durability unless given.
     */
    public func withDurability(durability: Durability): Setter<T> {
        this.durability = durability
        this
    }

    /**
     * Cancels what other handles compute, waits for them all to close, then sets the field in a new
     * revision. Returns the value it had.
     *
     * @throws IllegalStateException - if the handle is closed, or is inside a query
     */
    public func to(value: T): T {
        let revision = storage.beginWrite()
        try {
            let old = column.replace(id, value, durability, revision)
            storage.runtime.changed(old.durability.max(durability ?? old.durability), revision)
            old.value
        } finally {
            storage.endWrite()
        }
    }
}

/**
 * The rows of one `@Input` type in one database. Its columns share its lock.
 */
class InputTable <: Ingredient {
    let lock = Mutex()
    var rows: Int64 = 0

    InputTable(let name: String) {}

    public func maybeChangedAfter(_: Database, _: Id, _: Int64): Bool {
        false
    }

    public func describe(id: Id): String {
        "${name}(${id})"
    }
}

class Stamp<T> {
    Stamp(let value: T, let changedAt: Int64, let durability: Durability) {}
}

/**
 * One field of an `@Input` type in one database.
 */
class InputColumn<T> <: Ingredient {
    private let stamps = ArrayList<Stamp<T>>()

    InputColumn(let table: InputTable, let index: Int64, let field: String) {}

    func get(storage: Storage, id: Id): T {
        let stamp = synchronized(table.lock) {
            stamps[id.index]
        }
        storage.reportRead(DatabaseKey(index, id), stamp.durability, stamp.changedAt)
        stamp.value
    }

    /**
     * Called with the table's lock held, for the row being added.
     */
    func push(id: Id, stamp: Stamp<T>): Unit {
        if (id.index != stamps.size) {
            throw IllegalStateException("${table.name}.${field} is given row ${id} where row ${stamps.size} is due")
        }
        stamps.add(stamp)
    }

    /**
     * Returns the stamp replaced.
     */
    func replace(id: Id, value: T, durability: ?Durability, revision: Int64): Stamp<T> {
        synchronized(table.lock) {
            let old = stamps[id.index]
            stamps[id.index] = Stamp(value, revision, durability ?? old.durability)
            old
        }
    }

    public func maybeChangedAfter(_: Database, id: Id, revision: Int64): Bool {
        synchronized(table.lock) {
            stamps[id.index].changedAt > revision
        }
    }

    public func describe(id: Id): String {
        "${table.name}(${id}).${field}"
    }
}
