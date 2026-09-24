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

    private let gate = Mutex()
    private let released: Condition
    private var handles: Int64 = 0
    private let writePending = AtomicBool(false)

    init() {
        gate.lock()
        released = gate.condition()
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
        match (found as I) {
            case Some(ingredient) => ingredient
            case None => throw IllegalStateException("ingredient ${index} is ${found.describe(Id(0))}'s, of another type")
        }
    }

    func ingredientAt(index: Int64): Ingredient {
        lookup(index).getOrThrow {=> IllegalStateException("no ingredient ${index} in this database")}
    }

    private func lookup(index: Int64): ?Ingredient {
        let entries = table.load().entries
        if (index < entries.size) {
            entries[index]
        } else {
            None
        }
    }

    private func register(index: Int64, ingredient: Ingredient): Unit {
        let entries = table.load().entries
        let grown = Array<?Ingredient>(max(entries.size, index + 1), {i => if (i < entries.size) { entries[i] } else { None }})
        grown[index] = ingredient
        table.store(IngredientTable(grown))
    }

    func attach(): Unit {
        synchronized(gate) {
            handles++
        }
    }

    func detach(): Unit {
        synchronized(gate) {
            handles--
            released.notifyAll()
        }
    }

    /**
     * Cancels the queries of every other handle, waits for all of them to close, and opens a new
     * revision, which it returns.
     */
    func beginWrite(): Int64 {
        writePending.store(true)
        synchronized(gate) {
            while (handles > 1) {
                released.wait()
            }
        }
        revision_.fetchAdd(1) + 1
    }

    func endWrite(): Unit {
        writePending.store(false)
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

    func unwindIfCancelled(): Unit {
        if (writePending.load()) {
            throw Cancelled()
        }
    }
}
