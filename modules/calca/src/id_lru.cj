package calca

import std.collection.*

const NO_ID: Int64 = -1

/**
 * `prev` of an id that is not in the list.
 */
const ABSENT: Int64 = -2

/**
 * The keys of one tracked function in the order they were last used: `touch` makes one the most
 * recent, and `trim` evicts the oldest while there are more than `capacity`. Iteration goes from the
 * oldest to the most recent.
 *
 * `touch` never evicts, only `trim` does, so the caller decides when eviction happens — under the
 * write gate, while nothing reads. Until then the list may hold more than `capacity`.
 *
 * A doubly linked list over the ids themselves: `prev` and `next` are indexed by `Id.index`, which
 * is dense, since it is the key's index in the memo table. Nothing is hashed, and a touch is a few
 * array writes — a hash set in the order of use costs as much as the rest of a fetch that hits
 * (`IdLruBench`).
 *
 * Not thread-safe: `MemoTable` touches it under its lock.
 */
class IdLru <: Iterable<Id> {
    private let prev = ArrayList<Int64>()
    private let next = ArrayList<Int64>()

    /**
     * The least recently used, `NO_ID` when empty.
     */
    private var oldest = NO_ID

    /**
     * The most recently used, `NO_ID` when empty.
     */
    private var newest = NO_ID

    private var size_ = 0

    /**
     * @throws IllegalArgumentException - if `capacity` is negative
     */
    IdLru(let capacity: Int64) {
        if (capacity < 0) {
            throw IllegalArgumentException("a capacity is not negative: ${capacity}")
        }
    }

    prop size: Int64 {
        get() {
            size_
        }
    }

    func contains(id: Id): Bool {
        id.index < prev.size && prev[id.index] != ABSENT
    }

    /**
     * Makes `id` the most recently used, adding it if it is not there. Evicts nothing.
     */
    func touch(id: Id): Unit {
        let i = id.index
        while (prev.size <= i) {
            prev.add(ABSENT)
            next.add(NO_ID)
        }
        if (prev[i] == ABSENT) {
            size_++
        } else if (i == newest) {
            return
        } else {
            unlink(i)
        }
        prev[i] = newest
        next[i] = NO_ID
        if (newest == NO_ID) {
            oldest = i
        } else {
            next[newest] = i
        }
        newest = i
    }

    /**
     * Evicts the least recently used ids while there are more than `capacity`, handing each one to
     * `onEvict`, oldest first.
     */
    func trim(onEvict: (Id) -> Unit): Unit {
        while (size_ > capacity) {
            let i = oldest
            unlink(i)
            prev[i] = ABSENT
            size_--
            onEvict(Id(i))
        }
    }

    /**
     * The ids, from the least recently used to the most.
     */
    public func iterator(): Iterator<Id> {
        IdLruIterator(next, oldest)
    }

    private func unlink(i: Int64): Unit {
        let before = prev[i]
        let after = next[i]
        if (before == NO_ID) {
            oldest = after
        } else {
            next[before] = after
        }
        if (after == NO_ID) {
            newest = before
        } else {
            prev[after] = before
        }
    }
}

class IdLruIterator <: Iterator<Id> {
    IdLruIterator(let next_: ArrayList<Int64>, var index: Int64) {}

    public func next(): ?Id {
        if (index == NO_ID) {
            return None
        }
        let id = Id(index)
        index = next_[index]
        id
    }
}
