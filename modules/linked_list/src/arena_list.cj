package linked_list

import std.collection.*

/**
 * One element of an `ArenaList`, as long as it stays there: its slot, and the generation the slot was
 * in when the element was added. A slot is reused once its element is removed, and its generation goes
 * up, so a handle to a removed element never reaches the one added in its place.
 */
public struct ArenaHandle <: Equatable<ArenaHandle> & Hashable & ToString {
    ArenaHandle(
        /** The slot, dense from 0: an index for an array beside the list. */
        public let slot: Int64,
        let generation: Int64
    ) {}

    public operator func ==(other: ArenaHandle): Bool {
        slot == other.slot && generation == other.generation
    }

    public operator func !=(other: ArenaHandle): Bool {
        !(this == other)
    }

    public func hashCode(): Int64 {
        var hasher = DefaultHasher()
        hasher.write(slot)
        hasher.write(generation)
        hasher.finish()
    }

    public func toString(): String {
        "${slot}#${generation}"
    }
}

/**
 * A doubly linked list of values in an arena: each value sits in a slot of an array, the order is an
 * `IndexLinkedList` over the slots, and adding one returns an `ArenaHandle` that finds it in O(1). Unlike
 * `std.collection.LinkedList`, an element moves without being taken out and added again — no node is
 * allocated for it, and its handle stays valid. A removed element's slot is reused.
 *
 * Every operation is O(1), iteration aside. Not thread-safe.
 */
public class ArenaList<T> <: Iterable<T> {
    private let order = IndexLinkedList()
    private let values = ArrayList<?T>()
    private let generations = ArrayList<Int64>()
    private let free = ArrayList<Int64>()

    public init() {}

    @Frozen
    public prop size: Int64 {
        get() {
            order.size
        }
    }

    @Frozen
    public func isEmpty(): Bool {
        order.isEmpty()
    }

    /**
     * The first element's handle, `None` when empty.
     */
    @Frozen
    public prop front: ?ArenaHandle {
        get() {
            order.front.map {slot => handleOf(slot)}
        }
    }

    /**
     * The last element's handle, `None` when empty.
     */
    @Frozen
    public prop back: ?ArenaHandle {
        get() {
            order.back.map {slot => handleOf(slot)}
        }
    }

    /**
     * Whether `handle` is an element of this list: not removed since, nor made by another list.
     */
    @Frozen
    public func contains(handle: ArenaHandle): Bool {
        handle.slot >= 0 && handle.slot < generations.size && generations[handle.slot] == handle.generation &&
            values[handle.slot].isSome()
    }

    /**
     * The value of `handle`'s element.
     *
     * @throws NoneValueException - if `handle` is not in the list
     */
    @Frozen
    public operator func [](handle: ArenaHandle): T {
        checkContains(handle)
        values[handle.slot].getOrThrow()
    }

    /**
     * Replaces the value of `handle`'s element, where it is.
     *
     * @throws NoneValueException - if `handle` is not in the list
     */
    @Frozen
    public operator func [](handle: ArenaHandle, value!: T): Unit {
        checkContains(handle)
        values[handle.slot] = value
    }

    /**
     * The handle after `handle`, `None` if it is the last.
     *
     * @throws NoneValueException - if `handle` is not in the list
     */
    @Frozen
    public func nextOf(handle: ArenaHandle): ?ArenaHandle {
        checkContains(handle)
        order.nextOf(handle.slot).map {slot => handleOf(slot)}
    }

    /**
     * The handle before `handle`, `None` if it is the first.
     *
     * @throws NoneValueException - if `handle` is not in the list
     */
    @Frozen
    public func prevOf(handle: ArenaHandle): ?ArenaHandle {
        checkContains(handle)
        order.prevOf(handle.slot).map {slot => handleOf(slot)}
    }

    /**
     * Adds `value` at the end.
     */
    @Frozen
    public func pushBack(value: T): ArenaHandle {
        let slot = allocate(value)
        order.moveToBack(slot)
        handleOf(slot)
    }

    /**
     * Adds `value` at the start.
     */
    @Frozen
    public func pushFront(value: T): ArenaHandle {
        let slot = allocate(value)
        order.moveToFront(slot)
        handleOf(slot)
    }

    /**
     * Makes `handle`'s element the last.
     *
     * @throws NoneValueException - if `handle` is not in the list
     */
    @Frozen
    public func moveToBack(handle: ArenaHandle): Unit {
        checkContains(handle)
        order.moveToBack(handle.slot)
    }

    /**
     * Makes `handle`'s element the first.
     *
     * @throws NoneValueException - if `handle` is not in the list
     */
    @Frozen
    public func moveToFront(handle: ArenaHandle): Unit {
        checkContains(handle)
        order.moveToFront(handle.slot)
    }

    /**
     * Takes `handle`'s element out of the list and returns its value; the handle is no longer valid.
     *
     * @throws NoneValueException - if `handle` is not in the list
     */
    @Frozen
    public func remove(handle: ArenaHandle): T {
        checkContains(handle)
        release(handle.slot)
    }

    /**
     * Takes the first element out of the list, `None` when empty.
     */
    @Frozen
    public func popFront(): ?T {
        order.front.map {slot => release(slot)}
    }

    /**
     * Takes the last element out of the list, `None` when empty.
     */
    @Frozen
    public func popBack(): ?T {
        order.back.map {slot => release(slot)}
    }

    /**
     * Empties the list. Every handle given out is no longer valid.
     */
    public func clear(): Unit {
        while (let Some(slot) <- order.front) {
            release(slot)
        }
    }

    /**
     * The values from the first to the last. The list must not change while it is iterated.
     */
    public func iterator(): Iterator<T> {
        let slots = order.iterator()
        ArenaListIterator<T>(values, slots)
    }

    /**
     * The handles from the first to the last. The list must not change while they are iterated.
     */
    public func handles(): Iterator<ArenaHandle> {
        let generations = this.generations
        order.iterator() |> map {slot: Int64 => ArenaHandle(slot, generations[slot])}
    }

    @Frozen
    private func handleOf(slot: Int64): ArenaHandle {
        ArenaHandle(slot, generations[slot])
    }

    @Frozen
    private func allocate(value: T): Int64 {
        if (!free.isEmpty()) {
            // read before removing: -O2 miscompiles a value taken from `remove`'s result
            let slot = free[free.size - 1]
            free.remove(at: free.size - 1)
            values[slot] = value
            return slot
        }
        values.add(value)
        generations.add(0)
        values.size - 1
    }

    @Frozen
    private func release(slot: Int64): T {
        let value = values[slot].getOrThrow()
        order.remove(slot)
        values[slot] = None
        generations[slot]++
        free.add(slot)
        value
    }

    @Frozen
    private func checkContains(handle: ArenaHandle): Unit {
        if (!contains(handle)) {
            throw NoneValueException("${handle} is not in the list")
        }
    }
}

class ArenaListIterator<T> <: Iterator<T> {
    ArenaListIterator(let values: ArrayList<?T>, let slots: Iterator<Int64>) {}

    public func next(): ?T {
        slots.next().map {slot => values[slot].getOrThrow()}
    }
}
