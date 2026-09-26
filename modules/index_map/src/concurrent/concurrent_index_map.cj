package index_map.concurrent

import std.collection.*
import std.collection.concurrent.ConcurrentHashMap
import std.math.leadingZeros
import std.sync.*

// the first segment holds 2^FIRST_SEGMENT_BITS entries, each next one twice as many as the last
const FIRST_SEGMENT_BITS = 4

// enough segments for any index an `Int64` can hold
const SEGMENTS = 64 - FIRST_SEGMENT_BITS

/**
 * An `IndexMap` safe to share between threads, for what is only ever added to: interning, where an
 * entry's index is an id handed out for good. Reads (`get`, `indexOf`, `getAt`, `size`) take no
 * lock; `add` takes one only for a key not there yet, to give it the next index.
 *
 * There is no removing, and an entry's value never changes once added: a reader holding no lock
 * could otherwise see half of one. The entries live in segments of doubling size that never move, so
 * growing copies nothing and a reader never meets a table being replaced.
 */
public class ConcurrentIndexMap<K, V> where K <: Hashable & Equatable<K> {
    let indices = ConcurrentHashMap<K, Int64>()
    // segment `s` holds the entries from `2^(s + FIRST_SEGMENT_BITS) - 2^FIRST_SEGMENT_BITS` on;
    // one is set, as its entries are, before `count` says they are there
    let segments = Array<?Array<?(K, V)>>(SEGMENTS, repeat: None)
    let count = AtomicInt64(0)
    let lock = Mutex()

    public init() {}

    @Frozen
    public prop size: Int64 {
        get() {
            count.load()
        }
    }

    @Frozen
    public func isEmpty(): Bool {
        count.load() == 0
    }

    /**
     * The position of `key`'s entry.
     */
    @Frozen
    public func indexOf(key: K): ?Int64 {
        indices.get(key)
    }

    @Frozen
    public func contains(key: K): Bool {
        indices.contains(key)
    }

    @Frozen
    public func get(key: K): ?V {
        match (indices.get(key)) {
            case Some(index) => entry(index)[1]
            case None => None
        }
    }

    /**
     * The entry at `index`, or `None` if there is none there yet.
     */
    @Frozen
    public func getAt(index: Int64): ?(K, V) {
        if (index < 0 || index >= count.load()) {
            return None
        }
        entry(index)
    }

    /**
     * Appends an entry for a new `key`; one already there keeps its value.
     *
     * @return the value already there, if any
     */
    public func add(key: K, value: V): ?V {
        addWithIndex(key, value)[1]
    }

    /**
     * As `add`.
     *
     * @return the position of `key`'s entry, and the value already there, if any
     */
    @Frozen
    public func addWithIndex(key: K, value: V): (Int64, ?V) {
        match (indices.get(key)) {
            case Some(index) => (index, entry(index)[1])
            case None => append(key, value)
        }
    }

    /**
     * The entries there when it was called, in order.
     */
    public func iterator(): Iterator<(K, V)> {
        let size = count.load()
        (0..size).iterator().map {index => entry(index)}
    }

    public func toArray(): Array<(K, V)> {
        let size = count.load()
        Array(size) {index => entry(index)}
    }

    @Frozen
    func entry(index: Int64): (K, V) {
        let offset = index + (1 << FIRST_SEGMENT_BITS)
        let segment = 63 - Int64(leadingZeros(offset)) - FIRST_SEGMENT_BITS
        let start = 1 << (segment + FIRST_SEGMENT_BITS)
        segments[segment].getOrThrow()[offset - start].getOrThrow()
    }

    func append(key: K, value: V): (Int64, ?V) {
        synchronized(lock) {
            // another thread may have added it meanwhile
            if (let Some(index) <- indices.get(key)) {
                return (index, entry(index)[1])
            }
            let index = count.load()
            let offset = index + (1 << FIRST_SEGMENT_BITS)
            let segment = 63 - Int64(leadingZeros(offset)) - FIRST_SEGMENT_BITS
            let start = 1 << (segment + FIRST_SEGMENT_BITS)
            if (segments[segment].isNone()) {
                segments[segment] = Array<?(K, V)>(start, repeat: None)
            }
            segments[segment].getOrThrow()[offset - start] = (key, value)
            // the entry first, then its index: whoever finds the index finds the entry
            count.store(index + 1)
            indices.add(key, index)
            (index, None)
        }
    }
}

/**
 * An `IndexSet` safe to share between threads, as `ConcurrentIndexMap` is: an interner. Reads take no
 * lock, adding a new element takes one, and nothing is ever removed.
 */
public class ConcurrentIndexSet<T> where T <: Hashable & Equatable<T> {
    let map = ConcurrentIndexMap<T, Unit>()

    public init() {}

    @Frozen
    public prop size: Int64 {
        get() {
            map.size
        }
    }

    @Frozen
    public func isEmpty(): Bool {
        map.isEmpty()
    }

    /**
     * The position of `element`.
     */
    @Frozen
    public func indexOf(element: T): ?Int64 {
        map.indexOf(element)
    }

    @Frozen
    public func contains(element: T): Bool {
        map.contains(element)
    }

    /**
     * The element at `index`, or `None` if there is none there yet.
     */
    @Frozen
    public func getAt(index: Int64): ?T {
        match (map.getAt(index)) {
            case Some((element, _)) => element
            case None => None
        }
    }

    /**
     * Appends `element` if it is new; one already there keeps its place.
     *
     * @return whether it was new
     */
    public func add(element: T): Bool {
        addWithIndex(element)[1]
    }

    /**
     * As `add`.
     *
     * @return the position of `element`, and whether it was new
     */
    @Frozen
    public func addWithIndex(element: T): (Int64, Bool) {
        let (index, there) = map.addWithIndex(element, ())
        (index, there.isNone())
    }

    /**
     * The elements there when it was called, in order.
     */
    public func iterator(): Iterator<T> {
        map.iterator().map {entry => entry[0]}
    }

    public func toArray(): Array<T> {
        map.toArray().map {entry => entry[0]}
    }
}
