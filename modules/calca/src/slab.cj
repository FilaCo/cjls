package calca

import std.collection.*

/**
 * `next` of a vacant slot that is never reused: its generation ran out.
 */
const RETIRED: Int64 = -2

/**
 * A slot of a `Slab`, with its generation: a value, or, vacant, the index of the next vacant slot.
 */
enum SlabSlot<T> {
    | SlabOccupied(UInt32, T)
    | SlabVacant(UInt32, Int64)
}

/**
 * Values under `Id`s that are reused once the value is removed, each time with one more generation,
 * so an `Id` of a removed value never finds the one that took its slot. As `slotmap` and salsa's
 * interned tables do.
 *
 * The free list is implicit, the vacant slots themselves (it costs nothing beyond them), and LIFO:
 * the slot vacated last is the next one taken. A slot whose generation has reached
 * `maxGeneration` is retired rather than reused, which leaks one slot every 2³² reuses.
 *
 * Not thread-safe: its owner locks it.
 */
class Slab<T> {
    private let slots = ArrayList<SlabSlot<T>>()
    private var freeHead = NO_ID
    private var size_ = 0

    /**
     * Lowered by tests, to reach it.
     */
    var maxGeneration = UInt32.Max

    /**
     * How many values it holds.
     */
    prop size: Int64 {
        get() {
            size_
        }
    }

    /**
     * How many slots it has, occupied or not.
     */
    prop slotCount: Int64 {
        get() {
            slots.size
        }
    }

    /**
     * Puts `value` in the slot vacated last, or a new one.
     */
    func insert(value: T): Id {
        size_++
        if (freeHead == NO_ID) {
            let id = Id(slots.size)
            slots.add(SlabOccupied(0, value))
            return id
        }
        let index = freeHead
        match (slots[index]) {
            case SlabVacant(generation, next) =>
                freeHead = next
                slots[index] = SlabOccupied(generation, value)
                Id(index, generation: generation)
            case SlabOccupied(_, _) => throw IllegalStateException("slot ${index} is on the free list, and occupied")
        }
    }

    /**
     * The value at `id`, `None` once it was removed.
     */
    func get(id: Id): ?T {
        match (slots.get(id.index)) {
            case Some(SlabOccupied(generation, value)) where generation == id.generation => value
            case _ => None
        }
    }

    /**
     * The value in slot `index`, whatever its generation, and its `Id`.
     */
    func getAt(index: Int64): ?(Id, T) {
        match (slots.get(index)) {
            case Some(SlabOccupied(generation, value)) => (Id(index, generation: generation), value)
            case _ => None
        }
    }

    /**
     * Removes the value at `id`, and gives its slot the next generation. Returns it, `None` if it
     * was not there.
     */
    func remove(id: Id): ?T {
        let value = get(id) ?? return None
        let generation = id.generation
        if (generation == maxGeneration) {
            slots[id.index] = SlabVacant(generation, RETIRED)
        } else {
            slots[id.index] = SlabVacant(generation + 1, freeHead)
            freeHead = id.index
        }
        size_--
        value
    }
}
