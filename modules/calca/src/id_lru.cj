package calca

import std.collection.*
import linked_list.IndexLinkedList

/**
 * The keys of one tracked function in the order they were last used: `touch` makes one the most
 * recent, and `trim` evicts the oldest while there are more than `capacity`. Iteration goes from the
 * oldest to the most recent.
 *
 * `touch` never evicts, only `trim` does, so the caller decides when eviction happens — under the
 * write gate, while nothing reads. Until then the list may hold more than `capacity`.
 *
 * An `IndexLinkedList` over `Id.index`, which is dense, since it is the key's index in the memo
 * table: the ids themselves are the nodes. Nothing is hashed, and a touch is a few array writes — a
 * hash set in the order of use costs as much as the rest of a fetch that hits (`IdLruBench`).
 *
 * Not thread-safe: `MemoTable` touches it under its lock.
 */
class IdLru <: Iterable<Id> {
    private let order = IndexLinkedList()

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
            order.size
        }
    }

    func contains(id: Id): Bool {
        order.contains(id.index)
    }

    /**
     * Makes `id` the most recently used, adding it if it is not there. Evicts nothing.
     */
    func touch(id: Id): Unit {
        order.moveToBack(id.index)
    }

    /**
     * Evicts the least recently used ids while there are more than `capacity`, handing each one to
     * `onEvict`, oldest first.
     */
    func trim(onEvict: (Id) -> Unit): Unit {
        while (order.size > capacity) {
            onEvict(Id(order.popFront().getOrThrow()))
        }
    }

    /**
     * The ids, from the least recently used to the most.
     */
    public func iterator(): Iterator<Id> {
        order.iterator() |> map {index: Int64 => Id(index)}
    }
}
