package linked_list

import std.collection.*

/**
 * The end of the list: `prev` of the first index, `next` of the last, and `front`/`back` of an empty list.
 */
const END: Int64 = -1

/**
 * `prev` of an index that is not in the list.
 */
const ABSENT: Int64 = -2

/**
 * A doubly linked list over non-negative indices, the indices themselves being its nodes: `prev` and
 * `next` are arrays indexed by them. An index is in the list at most once. Nothing is allocated but the
 * two arrays, which grow to the largest index ever added, so it is meant for dense indices — an interned
 * value's, a slot's.
 *
 * Every operation is O(1), iteration aside. Not thread-safe.
 */
public class IndexLinkedList <: Iterable<Int64> {
    private let prev = ArrayList<Int64>()
    private let next = ArrayList<Int64>()
    private var front_ = END
    private var back_ = END
    private var size_ = 0

    public init() {}

    @Frozen
    public prop size: Int64 {
        get() {
            size_
        }
    }

    @Frozen
    public func isEmpty(): Bool {
        size_ == 0
    }

    /**
     * The first index, `None` when empty.
     */
    @Frozen
    public prop front: ?Int64 {
        get() {
            orNone(front_)
        }
    }

    /**
     * The last index, `None` when empty.
     */
    @Frozen
    public prop back: ?Int64 {
        get() {
            orNone(back_)
        }
    }

    @Frozen
    public func contains(index: Int64): Bool {
        index >= 0 && index < prev.size && prev[index] != ABSENT
    }

    /**
     * The index after `index`, `None` if it is the last.
     *
     * @throws NoneValueException - if `index` is not in the list
     */
    @Frozen
    public func nextOf(index: Int64): ?Int64 {
        checkContains(index)
        orNone(next[index])
    }

    /**
     * The index before `index`, `None` if it is the first.
     *
     * @throws NoneValueException - if `index` is not in the list
     */
    @Frozen
    public func prevOf(index: Int64): ?Int64 {
        checkContains(index)
        orNone(prev[index])
    }

    /**
     * Makes `index` the last, adding it if it is not in the list.
     *
     * @throws IllegalArgumentException - if `index` is negative
     */
    @Frozen
    public func moveToBack(index: Int64): Unit {
        checkIndex(index)
        if (index == back_) {
            return
        }
        detachOrAdd(index)
        prev[index] = back_
        next[index] = END
        if (back_ == END) {
            front_ = index
        } else {
            next[back_] = index
        }
        back_ = index
    }

    /**
     * Makes `index` the first, adding it if it is not in the list.
     *
     * @throws IllegalArgumentException - if `index` is negative
     */
    @Frozen
    public func moveToFront(index: Int64): Unit {
        checkIndex(index)
        if (index == front_) {
            return
        }
        detachOrAdd(index)
        prev[index] = END
        next[index] = front_
        if (front_ == END) {
            back_ = index
        } else {
            prev[front_] = index
        }
        front_ = index
    }

    /**
     * Takes `index` out of the list; `false` if it was not there.
     */
    @Frozen
    public func remove(index: Int64): Bool {
        if (!contains(index)) {
            return false
        }
        unlink(index)
        prev[index] = ABSENT
        size_--
        true
    }

    /**
     * Takes the first index out of the list, `None` when empty.
     */
    @Frozen
    public func popFront(): ?Int64 {
        let index = front_
        if (index == END) {
            return None
        }
        remove(index)
        index
    }

    /**
     * Takes the last index out of the list, `None` when empty.
     */
    @Frozen
    public func popBack(): ?Int64 {
        let index = back_
        if (index == END) {
            return None
        }
        remove(index)
        index
    }

    /**
     * Empties the list, keeping the arrays' capacity.
     */
    public func clear(): Unit {
        for (i in 0..prev.size) {
            prev[i] = ABSENT
        }
        front_ = END
        back_ = END
        size_ = 0
    }

    /**
     * The indices from the first to the last. The list must not change while it is iterated.
     */
    public func iterator(): Iterator<Int64> {
        IndexLinkedListIterator(next, front_)
    }

    /**
     * Unlinks `index` if it is in the list, else makes room for it and counts it in.
     */
    @Frozen
    private func detachOrAdd(index: Int64): Unit {
        while (prev.size <= index) {
            prev.add(ABSENT)
            next.add(END)
        }
        if (prev[index] == ABSENT) {
            size_++
        } else {
            unlink(index)
        }
    }

    @Frozen
    private func unlink(index: Int64): Unit {
        let before = prev[index]
        let after = next[index]
        if (before == END) {
            front_ = after
        } else {
            next[before] = after
        }
        if (after == END) {
            back_ = before
        } else {
            prev[after] = before
        }
    }

    @Frozen
    private func checkIndex(index: Int64): Unit {
        if (index < 0) {
            throw IllegalArgumentException("an index in a list is not negative: ${index}")
        }
    }

    @Frozen
    private func checkContains(index: Int64): Unit {
        if (!contains(index)) {
            throw NoneValueException("${index} is not in the list")
        }
    }
}

@Frozen
func orNone(index: Int64): ?Int64 {
    if (index == END) {
        None
    } else {
        index
    }
}

class IndexLinkedListIterator <: Iterator<Int64> {
    IndexLinkedListIterator(let links: ArrayList<Int64>, var current: Int64) {}

    public func next(): ?Int64 {
        let index = current
        if (index == END) {
            return None
        }
        current = links[index]
        index
    }
}
