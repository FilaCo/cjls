package calca

import std.collection.*
import std.sync.*

const FIRST_REVISION: Int64 = 1

let nextIngredient = AtomicInt64(0)

/**
 * Reserves `count` consecutive ingredient indices, process-wide, so the one index of an ingredient
 * names it in every database. Called once per `@CalcaInput` type and `@CalcaTracked` function, from the
 * static the macro gives it; the order of those calls decides only which numbers they get.
 */
func reserveIngredients(count: Int64): Int64 {
    nextIngredient.fetchAdd(count)
}

/**
 * The part of a database one input field or one tracked function keeps: its values, and how to
 * tell whether one of them changed.
 */
interface Ingredient {
    /**
     * Whether the value at `id` may have changed after `revision`. For a tracked function that may
     * mean verifying its memo, or executing it again, on `db`.
     */
    func maybeChangedAfter(db: Database, id: Id, revision: Int64): Bool

    func describe(id: Id): String

    /**
     * Called as a write opens a new revision, while nothing reads: when an ingredient lets go of
     * what it no longer needs.
     */
    func newRevision(): Unit {}
}

class IngredientTable {
    IngredientTable(let entries: Array<?Ingredient>) {}
}

/**
 * What every handle of one database shares: the revision, the ingredients, and the gate a write
 * goes through.
 */
class Runtime {
    private let revision_ = AtomicInt64(FIRST_REVISION)

    /**
     * For every durability, the last revision in which an input of at least that durability changed.
     */
    private let lastChanged = Array<AtomicInt64>(DURABILITIES, {_ => AtomicInt64(FIRST_REVISION)})

    /**
     * Copied on write, so the lookup every query makes takes no lock.
     */
    private let table = AtomicReference<IngredientTable>(IngredientTable([]))
    private let tableLock = Mutex()

    /**
     * What a write goes through: it waits here for every operation in flight to end, and one that
     * begins meanwhile is cancelled.
     */
    private let gate = Mutex()
    private let drained: Condition
    private var inFlight: Int64 = 0
    private let writePending = AtomicBool(false)

    Runtime() {
        gate.lock()
        drained = gate.condition()
        gate.unlock()
    }

    prop revision: Int64 {
        get() {
            revision_.load()
        }
    }

    func lastChangedAt(durability: Durability): Int64 {
        lastChanged[durability.rank].load()
    }

    func ingredient<I>(index: Int64, create: () -> I): I where I <: Ingredient {
        let found = match (lookup(index)) {
            case Some(ingredient) => ingredient
            case None => synchronized(tableLock) {
                match (lookup(index)) {
                    case Some(ingredient) => ingredient
                    case None =>
                        let created = create()
                        register(index, created)
                        created
                }
            }
        }
        (found as I).getOrThrow {=> IllegalStateException("ingredient ${index} is ${found.describe(Id(0))}'s, of another type")}
    }

    func ingredientAt(index: Int64): Ingredient {
        lookup(index).getOrThrow {=> IllegalStateException("no ingredient ${index} in this database")}
    }

    private func lookup(index: Int64): ?Ingredient {
        table.load().entries.get(index) ?? None
    }

    private func register(index: Int64, ingredient: Ingredient): Unit {
        let entries = table.load().entries
        let grown = Array<?Ingredient>(max(entries.size, index + 1), {i => entries.get(i) ?? None})
        grown[index] = ingredient
        table.store(IngredientTable(grown))
    }

    /**
     * Begins an operation of a handle outside any query, which a write waits for.
     *
     * @throws Cancelled - if a write is pending, or the handle is pinned to a revision gone by
     */
    func beginRead(pinned: ?Int64): Unit {
        synchronized(gate) {
            unwindIfCancelled(pinned)
            inFlight++
        }
    }

    func endRead(): Unit {
        synchronized(gate) {
            inFlight--
            if (inFlight == 0) {
                drained.notifyAll()
            }
        }
    }

    /**
     * Cancels the operations in flight, waits for them to end, and makes `change` in a new
     * revision, which it is given. Holds the gate throughout, so nothing begins until it is done;
     * the ingredients let go of what they no longer need then, with nothing reading them.
     */
    func write<T>(change: (Int64) -> T): T {
        synchronized(gate) {
            writePending.store(true)
            try {
                while (inFlight > 0) {
                    drained.wait()
                }
                for (ingredient in table.load().entries) {
                    ingredient?.newRevision()
                }
                change(revision_.fetchAdd(1) + 1)
            } finally {
                writePending.store(false)
            }
        }
    }

    /**
     * Records that an input of `durability` changed in `revision`, which makes every memo that read
     * inputs of that durability or a lower one verify its dependencies again.
     */
    func changed(durability: Durability, revision: Int64): Unit {
        for (rank in 0..=durability.rank) {
            lastChanged[rank].store(revision)
        }
    }

    /**
     * @throws Cancelled - if a write is pending, or `pinned` is a revision gone by
     */
    func unwindIfCancelled(pinned: ?Int64): Unit {
        if (writePending.load()) {
            throw Cancelled()
        }
        if (let Some(revision) <- pinned) {
            if (revision != this.revision) {
                throw Cancelled()
            }
        }
    }
}
