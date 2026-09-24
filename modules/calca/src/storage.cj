package calca

import std.collection.*
import std.sync.*

/**
 * What a database is to the code `@CalcaInput` and `@CalcaTracked` generate: something that hands out its
 * `Storage`. A project declares its own interface on top of it, for the tracked functions to take,
 * and a class implementing that:
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
     * Throws `Cancelled` if a write is waiting for this handle to close. Every query already checks;
     * this is for long computations of one's own between them.
     */
    func unwindIfCancelled(): Unit {
        storage.unwindIfCancelled()
    }
}

/**
 * One handle of a database: the state all handles share, and what this one is computing. A handle
 * is used from one thread at a time; `snapshot` gives another thread a handle of its own.
 *
 * Changing an input waits for every other handle to close, after cancelling what they compute, so
 * every snapshot must be closed, or the next write waits forever.
 */
public class Storage <: Resource {
    let runtime: Runtime
    private let stack = ArrayList<ActiveQuery>()
    private let active = HashSet<DatabaseKey>()
    private let closed = AtomicBool(false)

    public init() {
        this(Runtime())
    }

    private init(runtime: Runtime) {
        this.runtime = runtime
        runtime.attach()
    }

    /**
     * Another handle of the same database, for another thread. It reads the revision that is
     * current until it is closed.
     *
     * @throws IllegalStateException - if this handle is closed
     */
    public func snapshot(): Storage {
        ensureOpen()
        Storage(runtime)
    }

    public func isClosed(): Bool {
        closed.load()
    }

    /**
     * Lets a write waiting on this handle proceed. Idempotent.
     */
    public func close(): Unit {
        if (closed.compareAndSwap(false, true)) {
            runtime.detach()
        }
    }

    /**
     * @throws Cancelled - if a write is waiting for this handle to close
     */
    public func unwindIfCancelled(): Unit {
        runtime.unwindIfCancelled()
    }

    func ensureOpen(): Unit {
        if (isClosed()) {
            throw IllegalStateException("the database handle is closed")
        }
    }

    /**
     * @throws IllegalStateException - if this handle is closed, or is inside a query
     */
    func beginWrite(): Int64 {
        ensureOpen()
        if (!active.isEmpty()) {
            throw IllegalStateException("an input cannot change while a query runs")
        }
        runtime.beginWrite()
    }

    func endWrite(): Unit {
        runtime.endWrite()
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
