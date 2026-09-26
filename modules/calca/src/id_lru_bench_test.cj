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
 * A revision's touches and the trim ending it, on `IdLru` and on the hash set it replaced.
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
