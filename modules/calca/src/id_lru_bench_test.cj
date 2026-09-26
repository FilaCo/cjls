package calca

import std.collection.*
import std.random.*
import std.unittest.*
import std.unittest.testmacro.*
import calca.macros.*
import linked_list.*

const NO_ID: Int64 = -1

/**
 * `prev` of an id that is not in the list.
 */
const ABSENT: Int64 = -2

/**
 * `IdLru` as it was before `linked_list` (D17): the same list, written out inside calca. The
 * baseline `IdLru` on `IndexLinkedList` is measured against, across the package boundary.
 */
class ArrayIdLru <: Iterable<Id> {
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
    ArrayIdLru(let capacity: Int64) {
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
        ArrayIdLruIterator(next, oldest)
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

class ArrayIdLruIterator <: Iterator<Id> {
    ArrayIdLruIterator(let next_: ArrayList<Int64>, var index: Int64) {}

    public func next(): ?Id {
        if (index == NO_ID) {
            return None
        }
        let id = Id(index)
        index = next_[index]
        id
    }
}

/**
 * The baseline `IdLru` replaced (D17): a hash set in the order of last use, the list kept in arrays
 * by slot, a slot freed by `trim` reused through a free list threaded through `next`. What calca
 * calls of it — `touch` and `trim` — and nothing else.
 */
class HashLru<T> where T <: Hashable & Equatable<T> {
    private let slots = HashMap<T, Int64>()
    private let values = ArrayList<?T>()
    private let prev = ArrayList<Int64>()
    private let next = ArrayList<Int64>()
    private var oldest = NO_ID
    private var newest = NO_ID
    private var freeHead = NO_ID

    HashLru(let capacity: Int64) {}

    func touch(value: T): Unit {
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

    func trim(onEvict: (T) -> Unit): Unit {
        while (slots.size > capacity) {
            let slot = oldest
            let value = values[slot].getOrThrow()
            slots.remove(value)
            unlink(slot)
            values[slot] = None
            prev[slot] = NO_ID
            next[slot] = freeHead
            freeHead = slot
            onEvict(value)
        }
    }

    private func allocate(value: T): Int64 {
        if (freeHead == NO_ID) {
            values.add(value)
            prev.add(NO_ID)
            next.add(NO_ID)
            return values.size - 1
        }
        let slot = freeHead
        freeHead = next[slot]
        values[slot] = value
        slot
    }

    private func append(slot: Int64): Unit {
        prev[slot] = newest
        next[slot] = NO_ID
        if (newest == NO_ID) {
            oldest = slot
        } else {
            next[newest] = slot
        }
        newest = slot
    }

    private func unlink(slot: Int64): Unit {
        let before = prev[slot]
        let after = next[slot]
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

/**
 * `std.collection.LinkedList` in the order of last use, its nodes found by `Id.index`. The list
 * cannot move a node, so a touch removes it and adds a new one at the end.
 */
class LinkedListLru {
    private let list = LinkedList<Id>()
    private let nodes = ArrayList<?LinkedListNode<Id>>()

    LinkedListLru(let capacity: Int64) {}

    func touch(id: Id): Unit {
        let i = id.index
        while (nodes.size <= i) {
            nodes.add(None)
        }
        if (let Some(node) <- nodes[i]) {
            list.remove(node)
        }
        nodes[i] = list.addLast(id)
    }

    func trim(onEvict: (Id) -> Unit): Unit {
        while (list.size > capacity) {
            let id = list.removeFirst().getOrThrow()
            nodes[id.index] = None
            onEvict(id)
        }
    }
}

/**
 * The textbook LRU: `std.collection.LinkedList` and a `HashMap` from a key to its node.
 */
class HashLinkedListLru<T> where T <: Hashable & Equatable<T> {
    private let list = LinkedList<T>()
    private let nodes = HashMap<T, LinkedListNode<T>>()

    HashLinkedListLru(let capacity: Int64) {}

    func touch(value: T): Unit {
        if (let Some(node) <- nodes.get(value)) {
            list.remove(node)
        }
        nodes.add(value, list.addLast(value))
    }

    func trim(onEvict: (T) -> Unit): Unit {
        while (list.size > capacity) {
            let value = list.removeFirst().getOrThrow()
            nodes.remove(value)
            onEvict(value)
        }
    }
}

/**
 * `linked_list.ArenaList` in the order of last use, its handles found by `Id.index`: what
 * `std.collection.LinkedList` would be if it could move a node.
 */
class ArenaListLru {
    private let list = ArenaList<Id>()
    private let handles = ArrayList<?ArenaHandle>()

    ArenaListLru(let capacity: Int64) {}

    func touch(id: Id): Unit {
        let i = id.index
        while (handles.size <= i) {
            handles.add(None)
        }
        match (handles[i]) {
            case Some(handle) => list.moveToBack(handle)
            case None => handles[i] = list.pushBack(id)
        }
    }

    func trim(onEvict: (Id) -> Unit): Unit {
        while (list.size > capacity) {
            let id = list.popFront().getOrThrow()
            handles[id.index] = None
            onEvict(id)
        }
    }
}

/**
 * The keys fetched in one revision: 4096 fetches over 256 keys, half of them among the first 64.
 */
let BENCH_IDS: Array<Id> = {
    =>
    let random = Random(42)
    Array<Id>(4096) {
        _ => Id(if (random.nextBool()) {
            random.nextInt64(64)
        } else {
            random.nextInt64(256)
        })
    }
}()

let BENCH_CAPACITY = 128

/**
 * A revision's touches and the trim ending it: on `IdLru` (an `IndexLinkedList`), on the same list
 * written out inside calca, on the hash set it replaced, on `ArenaList`, and on
 * `std.collection.LinkedList`.
 * `cjpm bench '--filter=IdLruBench.*'`.
 */
@Test
class IdLruBench {
    @Bench
    func idLru(): Int64 {
        let lru = IdLru(BENCH_CAPACITY)
        for (id in BENCH_IDS) {
            lru.touch(id)
        }
        let evicted = ArrayList<Id>()
        lru.trim {id => evicted.add(id)}
        evicted.size
    }

    @Bench
    func arrayIdLru(): Int64 {
        let lru = ArrayIdLru(BENCH_CAPACITY)
        for (id in BENCH_IDS) {
            lru.touch(id)
        }
        let evicted = ArrayList<Id>()
        lru.trim {id => evicted.add(id)}
        evicted.size
    }

    @Bench
    func arenaListLru(): Int64 {
        let lru = ArenaListLru(BENCH_CAPACITY)
        for (id in BENCH_IDS) {
            lru.touch(id)
        }
        let evicted = ArrayList<Id>()
        lru.trim {id => evicted.add(id)}
        evicted.size
    }

    @Bench
    func hashLru(): Int64 {
        let lru = HashLru<Id>(BENCH_CAPACITY)
        for (id in BENCH_IDS) {
            lru.touch(id)
        }
        let evicted = ArrayList<Id>()
        lru.trim {id => evicted.add(id)}
        evicted.size
    }

    @Bench
    func linkedListLru(): Int64 {
        let lru = LinkedListLru(BENCH_CAPACITY)
        for (id in BENCH_IDS) {
            lru.touch(id)
        }
        let evicted = ArrayList<Id>()
        lru.trim {id => evicted.add(id)}
        evicted.size
    }

    @Bench
    func hashLinkedListLru(): Int64 {
        let lru = HashLinkedListLru<Id>(BENCH_CAPACITY)
        for (id in BENCH_IDS) {
            lru.touch(id)
        }
        let evicted = ArrayList<Id>()
        lru.trim {id => evicted.add(id)}
        evicted.size
    }
}

@CalcaTracked[lru: 512]
func benchLruLength(db: TestDb, file: SourceFile): Int64 {
    file.text(db).size
}

@CalcaTracked
func benchLength(db: TestDb, file: SourceFile): Int64 {
    file.text(db).size
}

let BENCH_DB = TestDatabase()

let BENCH_FILES = Array<SourceFile>(256) {i => SourceFile(BENCH_DB, "${i}.cj", "text ${i}")}

/**
 * Fetches that hit, with `lru` (large enough to evict nothing) and without: what a touch adds to
 * one. The first batch computes, the warm-up absorbs it. `cjpm bench '--filter=LruFetchBench.*'`.
 */
@Test
class LruFetchBench {
    @Bench
    func hitsWithLru(): Int64 {
        var sum = 0
        for (file in BENCH_FILES) {
            sum += benchLruLength(BENCH_DB, file)
        }
        sum
    }

    @Bench
    func hitsWithoutLru(): Int64 {
        var sum = 0
        for (file in BENCH_FILES) {
            sum += benchLength(BENCH_DB, file)
        }
        sum
    }
}
