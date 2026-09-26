package lru_set

import std.collection.*
import std.deriving.*
import std.random.*
import std.unittest.*
import std.unittest.testmacro.*

/**
 * What calca's `Id` is: a derived-`Hashable` struct around a dense index.
 */
@Derive[Equatable, Hashable]
struct BenchId {
    BenchId(let index: Int64) {}
}

/**
 * The alternative measured: the order kept in arrays indexed by the dense id itself, no hash.
 */
class DenseLru {
    private let prev = ArrayList<Int64>()
    private let next = ArrayList<Int64>()
    private let present = ArrayList<Bool>()
    private var oldest = NIL
    private var newest = NIL
    private var size_ = 0

    DenseLru(let capacity: Int64) {}

    func touch(id: Int64): Unit {
        while (present.size <= id) {
            prev.add(NIL)
            next.add(NIL)
            present.add(false)
        }
        if (present[id]) {
            if (id == newest) {
                return
            }
            unlink(id)
        } else {
            present[id] = true
            size_++
        }
        prev[id] = newest
        next[id] = NIL
        if (newest == NIL) {
            oldest = id
        } else {
            next[newest] = id
        }
        newest = id
    }

    func trim(onEvict: (Int64) -> Unit): Unit {
        while (size_ > capacity) {
            let id = oldest
            unlink(id)
            present[id] = false
            size_--
            onEvict(id)
        }
    }

    private func unlink(id: Int64): Unit {
        let before = prev[id]
        let after = next[id]
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

/**
 * Keys touched in one revision: 4096 fetches over 256 keys, a quarter of them hot.
 */
let BENCH_KEYS: Array<Int64> = {
    =>
    let random = Random(42)
    Array<Int64>(4096) {
        _ => if (random.nextBool()) {
            random.nextInt64(64)
        } else {
            random.nextInt64(256)
        }
    }
}()

let BENCH_IDS = BENCH_KEYS.map {key => BenchId(key)}

let BENCH_CAPACITY = 128

/**
 * `LruSet` against a list indexed by the dense id: a revision of fetches, then its trim.
 * `cjpm bench '--filter=LruBench.*'`.
 */
@Test
class LruBench {
    @Bench
    func lruSetOfDerivedId(): Int64 {
        let set = LruSet<BenchId>(BENCH_CAPACITY)
        for (id in BENCH_IDS) {
            set.touch(id)
        }
        let evicted = ArrayList<Int64>()
        set.trim {_ => evicted.add(0)}
        evicted.size
    }

    @Bench
    func lruSetOfInt64(): Int64 {
        let set = LruSet<Int64>(BENCH_CAPACITY)
        for (key in BENCH_KEYS) {
            set.touch(key)
        }
        let evicted = ArrayList<Int64>()
        set.trim {_ => evicted.add(0)}
        evicted.size
    }

    @Bench
    func denseLru(): Int64 {
        let lru = DenseLru(BENCH_CAPACITY)
        for (key in BENCH_KEYS) {
            lru.touch(key)
        }
        let evicted = ArrayList<Int64>()
        lru.trim {_ => evicted.add(0)}
        evicted.size
    }
}
