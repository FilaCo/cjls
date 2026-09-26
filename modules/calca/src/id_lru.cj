package calca

import std.collection.*

const NO_ID: Int64 = -1

/**
 * The keys of one function in the order of last use, as a doubly linked list over their dense
 * `Id`s: `prev`/`next` are indexed by the id itself, so there is nothing to hash.
 */
class IdLru {
    private let prev = ArrayList<Int64>()
    private let next = ArrayList<Int64>()
    private let present = ArrayList<Bool>()
    private var oldest = NO_ID
    private var newest = NO_ID
    private var size = 0

    IdLru(let capacity: Int64) {}

    func touch(id: Id): Unit {
        let i = id.index
        while (present.size <= i) {
            prev.add(NO_ID)
            next.add(NO_ID)
            present.add(false)
        }
        if (present[i]) {
            if (i == newest) {
                return
            }
            unlink(i)
        } else {
            present[i] = true
            size++
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

    func trim(onEvict: (Id) -> Unit): Unit {
        while (size > capacity) {
            let i = oldest
            unlink(i)
            present[i] = false
            size--
            onEvict(Id(i))
        }
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
