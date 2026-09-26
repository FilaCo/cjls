package calca

import std.collection.*
import std.random.*
import std.unittest.*
import std.unittest.testmacro.*
import calca.macros.*

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
 * A linked list of our own, what `std.collection.LinkedList` would be if it could move a node: values
 * in the slots of an arena, `prev`/`next` arrays over the slots, a slot freed by `remove` reused, and a
 * handle carrying its slot's generation so that it never reaches a value added in its place. A move
 * allocates nothing.
 */
class ArenaList<T> {
    private let values = ArrayList<?T>()
    private let generations = ArrayList<Int64>()
    private let prev = ArrayList<Int64>()
    private let next = ArrayList<Int64>()
    private let free = ArrayList<Int64>()
    private var front = NO_ID
    private var back = NO_ID
    private var size_ = 0

    prop size: Int64 {
        get() {
            size_
        }
    }

    func pushBack(value: T): (Int64, Int64) {
        let slot = allocate(value)
        link(slot)
        size_++
        (slot, generations[slot])
    }

    func moveToBack(handle: (Int64, Int64)): Unit {
        let slot = check(handle)
        if (slot != back) {
            unlink(slot)
            link(slot)
        }
    }

    func remove(handle: (Int64, Int64)): T {
        release(check(handle))
    }

    func popFront(): ?T {
        if (front == NO_ID) {
            None
        } else {
            release(front)
        }
    }

    private func check(handle: (Int64, Int64)): Int64 {
        let (slot, generation) = handle
        if (slot < 0 || slot >= values.size || generations[slot] != generation || values[slot].isNone()) {
            throw NoneValueException("${slot}#${generation} is not in the list")
        }
        slot
    }

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
        prev.add(NO_ID)
        next.add(NO_ID)
        values.size - 1
    }

    private func release(slot: Int64): T {
        let value = values[slot].getOrThrow()
        unlink(slot)
        values[slot] = None
        generations[slot]++
        free.add(slot)
        size_--
        value
    }

    private func link(slot: Int64): Unit {
        prev[slot] = back
        next[slot] = NO_ID
        if (back == NO_ID) {
            front = slot
        } else {
            next[back] = slot
        }
        back = slot
    }

    private func unlink(slot: Int64): Unit {
        let before = prev[slot]
        let after = next[slot]
        if (before == NO_ID) {
            front = after
        } else {
            next[before] = after
        }
        if (after == NO_ID) {
            back = before
        } else {
            prev[after] = before
        }
    }
}

/**
 * `ArenaList` in the order of last use, its handles found by `Id.index`.
 */
class ArenaListLru {
    private let list = ArenaList<Id>()
    private let handles = ArrayList<?(Int64, Int64)>()

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
 * A revision's touches and the trim ending it, on `IdLru`, on the hash set it replaced, on a linked
 * list of our own (`ArenaList`), and on `std.collection.LinkedList`.
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
