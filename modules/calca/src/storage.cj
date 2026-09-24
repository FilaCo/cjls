package calca

import std.collection.*
import std.sync.*

/**
 * What a database is to the code `@CalcaInput`, `@CalcaInterned` and `@CalcaTracked` generate:
 * something that hands out its `Storage`. A project declares its own interface on top of it, for
 * the tracked functions to take, and a class implementing that:
 *
 * ```cangjie
 * public interface Db <: Database {}
 *
 * public class RootDatabase <: Db {
 *     private RootDatabase(private let storage_: Storage) {}
 *     public init() { this(Storage()) }
 *     public prop storage: Storage { get() { storage_ } }
 *     public func snapshot(): RootDatabase { RootDatabase(storage_.snapshot()) }
 * }
 * ```
 */
public interface Database {
    prop storage: Storage

    /**
     * Throws `Cancelled` if a write is pending, or this is a snapshot of a revision gone by. Every
     * query already checks; this is for long computations of one's own between them.
     */
    func unwindIfCancelled(): Unit {
        storage.unwindIfCancelled()
    }
}

/**
 * One handle of a database: the state all handles share, and what this one is computing. A handle
 * is used from one thread at a time.
 *
 * `Storage()` makes a database and its root handle, which always reads the current revision and is
 * the only one that changes inputs. `snapshot` gives another thread a handle pinned to the revision
 * current when it was taken. Changing an input cancels what is in flight on the snapshots and waits
 * for that to end, never for a snapshot as such: one used after it is simply `Cancelled`, so there
 * is nothing to close, and a snapshot forgotten holds up nothing.
 */
public class Storage {
    let runtime: Runtime

    /**
     * The revision of a snapshot, `None` for the root handle.
     */
    private let pinned: ?Int64
    private let stack = ArrayList<ActiveQuery>()
    private let active = HashSet<DatabaseKey>()

    /**
     * How many operations of this handle are nested in one another: only the outermost one goes
     * through the gate.
     */
    private var depth: Int64 = 0

    public init() {
        this(Runtime(), None)
    }

    private init(runtime: Runtime, pinned: ?Int64) {
        this.runtime = runtime
        this.pinned = pinned
    }

    /**
     * Another handle of the same database, for another thread, pinned to the revision this one
     * reads.
     */
    public func snapshot(): Storage {
        Storage(runtime, pinned ?? runtime.revision)
    }

    /**
     * @throws Cancelled - if a write is pending, or this is a snapshot of a revision gone by
     */
    public func unwindIfCancelled(): Unit {
        runtime.unwindIfCancelled(pinned)
    }

    /**
     * Runs one operation of this handle, which a write waits for if it is not inside another.
     *
     * @throws Cancelled - if a write is pending, or this is a snapshot of a revision gone by
     */
    func read<T>(operation: () -> T): T {
        let outermost = depth == 0
        if (outermost) {
            runtime.beginRead(pinned)
        } else {
            runtime.unwindIfCancelled(pinned)
        }
        depth++
        try {
            operation()
        } finally {
            depth--
            if (outermost) {
                runtime.endRead()
            }
        }
    }

    /**
     * Makes `change` in a new revision, once what is in flight on the snapshots has ended.
     *
     * @throws IllegalStateException - if this is a snapshot, or the handle is inside an operation
     */
    func write<T>(change: (Int64) -> T): T {
        checkWritable("change")
        runtime.write(change)
    }

    /**
     * Refuses to `action` an input from a snapshot, or inside an operation: only the root handle
     * makes inputs, and what a query computes depends on nothing but what it reads.
     *
     * @throws IllegalStateException - if this is a snapshot, or the handle is inside an operation
     */
    func checkWritable(action: String): Unit {
        if (pinned.isSome()) {
            throw IllegalStateException("a snapshot cannot ${action} an input")
        }
        if (depth > 0) {
            throw IllegalStateException("an input cannot ${action} while a query runs")
        }
    }

    /**
     * Marks `key` as being worked on by this handle until `exit`, verified or executed alike.
     *
     * @throws CycleException - if it already is
     */
    func enter(key: DatabaseKey): Unit {
        if (!active.add(key)) {
            let path = stack.map {frame => describe(frame.key)}
            path.add(describe(key))
            throw CycleException("cycle: ${String.join(path.toArray(), delimiter: " -> ")}")
        }
    }

    func exit(key: DatabaseKey): Unit {
        active.remove(key)
    }

    func push(key: DatabaseKey): ActiveQuery {
        let frame = ActiveQuery(key)
        stack.add(frame)
        frame
    }

    func pop(): Unit {
        stack.remove(at: stack.size - 1)
    }

    /**
     * Records a read on the query running, if any.
     */
    func reportRead(key: DatabaseKey, durability: Durability, changedAt: Int64): Unit {
        if (!stack.isEmpty()) {
            stack[stack.size - 1].read(key, durability, changedAt)
        }
    }

    private func describe(key: DatabaseKey): String {
        runtime.ingredientAt(key.ingredient).describe(key.id)
    }
}

/**
 * What a query running has read so far.
 */
class ActiveQuery {
    ActiveQuery(let key: DatabaseKey) {}

    let dependencies = ArrayList<DatabaseKey>()
    private let seen = HashSet<DatabaseKey>()
    var durability = Durability.High
    var changedAt = FIRST_REVISION

    func read(key: DatabaseKey, durability: Durability, changedAt: Int64): Unit {
        if (seen.add(key)) {
            dependencies.add(key)
        }
        this.durability = this.durability.min(durability)
        this.changedAt = max(this.changedAt, changedAt)
    }
}
