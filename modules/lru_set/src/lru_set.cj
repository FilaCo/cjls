package lru_set

import std.collection.*

const NIL: Int64 = -1

/**
 * A hash set that keeps its elements in the order they were last used: `touch` makes one the most
 * recent, and `trim` evicts the oldest while there are more than `capacity`. Iteration goes from
 * the oldest to the most recent.
 *
 * `touch` never evicts, only `trim` does, so the caller decides when eviction happens — calca, under
 * its write gate, while nothing reads. Until then the set may hold more than `capacity`.
 *
 * The order is a doubly linked list kept in arrays (`prev`, `next`) rather than an object per
 * element, and a slot freed by `remove` or `trim` is reused by the next new element: its `next`
 * holds the next free slot, so the free list costs nothing beyond the slots themselves.
 *
 * Not thread-safe, as `HashSet` is not: only the caller knows its locking.
 */
public class LruSet<T> <: Iterable<T> where T <: Hashable & Equatable<T> {
    private let slots = HashMap<T, Int64>()
    private let values = ArrayList<?T>()
    private let prev = ArrayList<Int64>()
    private let next = ArrayList<Int64>()

    /**
     * The least recently used, `NIL` when empty.
     */
    private var oldest = NIL

    /**
     * The most recently used, `NIL` when empty.
     */
    private var newest = NIL

    /**
     * The first vacant slot, `NIL` when there is none; each one's `next` is the one after it.
     */
    private var freeHead = NIL

    private var capacity_: Int64

    /**
     * @throws IllegalArgumentException - if `capacity` is negative
     */
    public init(capacity: Int64) {
        capacity_ = checked(capacity)
    }

    /**
     * How many elements `trim` keeps. A smaller one evicts nothing until the next `trim`.
     *
     * @throws IllegalArgumentException - if set negative
     */
    public mut prop capacity: Int64 {
        get() {
            capacity_
        }
        set(value) {
            capacity_ = checked(value)
        }
    }

    public prop size: Int64 {
        get() {
            slots.size
        }
    }

    /**
     * How many slots there are, vacant ones included: what the arrays hold.
     */
    prop slotCount: Int64 {
        get() {
            values.size
        }
    }

    public func isEmpty(): Bool {
        slots.isEmpty()
    }

    public func contains(value: T): Bool {
        slots.contains(value)
    }

    /**
     * Makes `value` the most recently used, adding it if it is not there. Evicts nothing.
     */
    public func touch(value: T): Unit {
        match (slots.get(value)) {
            case Some(slot) =>
                if (slot != newest) {
                    unlink(slot)
                    append(slot)
                }
            case None =>
                let slot = allocate(value)
                slots.add(value, slot)
                append(slot)
        }
    }

    /**
     * @return whether `value` was there
     */
    public func remove(value: T): Bool {
        match (slots.remove(value)) {
            case Some(slot) =>
                unlink(slot)
                release(slot)
                true
            case None => false
        }
    }

    /**
     * Evicts the least recently used elements while there are more than `capacity`, handing each
     * one to `onEvict`, oldest first.
     */
    public func trim(onEvict: (T) -> Unit): Unit {
        while (slots.size > capacity_) {
            let slot = oldest
            let value = values[slot].getOrThrow()
            slots.remove(value)
            unlink(slot)
            release(slot)
            onEvict(value)
        }
    }

    /**
     * The elements, from the least recently used to the most.
     */
    public func iterator(): Iterator<T> {
        LruSetIterator<T>(values, next, oldest)
    }

    private func allocate(value: T): Int64 {
        if (freeHead == NIL) {
            values.add(value)
            prev.add(NIL)
            next.add(NIL)
            return values.size - 1
        }
        let slot = freeHead
        freeHead = next[slot]
        values[slot] = value
        slot
    }

    private func release(slot: Int64): Unit {
        values[slot] = None
        prev[slot] = NIL
        next[slot] = freeHead
        freeHead = slot
    }

    /**
     * Puts the unlinked `slot` after the most recent.
     */
    private func append(slot: Int64): Unit {
        prev[slot] = newest
        next[slot] = NIL
        if (newest == NIL) {
            oldest = slot
        } else {
            next[newest] = slot
        }
        newest = slot
    }

    private func unlink(slot: Int64): Unit {
        let before = prev[slot]
        let after = next[slot]
        if (before == NIL) {
            oldest = after
        } else {
            next[before] = after
        }
        if (after == NIL) {
            newest = before
        } else {
            prev[after] = before
        }
    }
}

class LruSetIterator<T> <: Iterator<T> {
    LruSetIterator(let values: ArrayList<?T>, let next_: ArrayList<Int64>, var slot: Int64) {}

    public func next(): ?T {
        if (slot == NIL) {
            return None
        }
        let value = values[slot]
        slot = next_[slot]
        value
    }
}

private func checked(capacity: Int64): Int64 {
    if (capacity < 0) {
        throw IllegalArgumentException("a capacity is not negative: ${capacity}")
    }
    capacity
}
