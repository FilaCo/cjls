package index_map

import std.collection.*

/**
 * A hash map that keeps its entries in the order they were first added, the way Rust's `indexmap`
 * does, and so gives each one an index: its position in that order.
 *
 * Replacing the value of a key keeps its entry where it is. Removing one either shifts every later
 * entry down a place (`shiftRemove`, and `remove`: O(n), the order of the rest kept) or moves the
 * last entry into the gap (`swapRemove`: O(1)). Iteration, `keys()` and `values()` follow the order.
 *
 * Not thread-safe, as `HashMap` is not.
 */
public class IndexMap<K, V> <: Map<K, V> where K <: Hashable & Equatable<K> {
    private IndexMap(let entries: ArrayList<(K, V)>, private let indices: HashMap<K, Int64>) {}

    public init() {
        this(0)
    }

    /**
     * @throws IllegalArgumentException - if `capacity` is negative
     */
    public init(capacity: Int64) {
        this(ArrayList(capacity), HashMap(capacity))
    }

    /**
     * In the order of `elements`; a key met again replaces the value, not the place.
     */
    public init(elements: Collection<(K, V)>) {
        this(elements.size)
        add(all: elements)
    }

    public prop size: Int64 {
        get() {
            entries.size
        }
    }

    public func isEmpty(): Bool {
        entries.isEmpty()
    }

    public func iterator(): Iterator<(K, V)> {
        entries.iterator()
    }

    public func get(key: K): ?V {
        indices.get(key).map {index => entries[index][1]}
    }

    /**
     * The position of `key`'s entry.
     */
    public func indexOf(key: K): ?Int64 {
        indices.get(key)
    }

    /**
     * The entry at `index`, or `None` if there is none there.
     */
    public func getAt(index: Int64): ?(K, V) {
        entries.get(index)
    }

    public func contains(key: K): Bool {
        indices.contains(key)
    }

    public func contains(all!: Collection<K>): Bool {
        indices.contains(all: all)
    }

    /**
     * A view, in order: it sees later changes to the map.
     */
    public func keys(): EquatableCollection<K> {
        Keys(this)
    }

    /**
     * A view, in order: it sees later changes to the map.
     */
    public func values(): Collection<V> {
        Values(this)
    }

    /**
     * @throws NoneValueException - if there is no `key`
     */
    public operator func [](key: K): V {
        get(key).getOrThrow()
    }

    public operator func [](key: K, value!: V): Unit {
        add(key, value)
    }

    /**
     * Appends an entry for a new `key`; for one already there, replaces the value in place.
     *
     * @return the value replaced
     */
    public func add(key: K, value: V): ?V {
        addWithIndex(key, value)[1]
    }

    /**
     * As `add`.
     *
     * @return the position of `key`'s entry, and the value replaced
     */
    public func addWithIndex(key: K, value: V): (Int64, ?V) {
        match (indices.get(key)) {
            case Some(index) =>
                let (kept, replaced) = entries[index]
                // the key first added stays, as `HashMap` keeps it
                entries[index] = (kept, value)
                (index, replaced)
            case None =>
                entries.add((key, value))
                indices.add(key, entries.size - 1)
                (entries.size - 1, None)
        }
    }

    public func add(all!: Collection<(K, V)>): Unit {
        all.iterator().forEach {entry => add(entry[0], entry[1])}
    }

    /**
     * As `shiftRemove`: the order of the rest is kept.
     */
    public func remove(key: K): ?V {
        shiftRemove(key)
    }

    public func remove(all!: Collection<K>): Unit {
        let doomed = HashSet(all)
        removeIf {key, _ => doomed.contains(key)}
    }

    /**
     * Removes `key`'s entry and shifts every later one down a place. O(n).
     *
     * @return the value removed
     */
    public func shiftRemove(key: K): ?V {
        let index = indices.remove(key) ?? return None
        // read before removing: at -O2, cjc 1.3.0-alpha miscompiles a tuple taken apart straight
        // from `ArrayList.remove`, handing back the entry that moved into its place
        let (_, removed) = entries[index]
        entries.remove(at: index)
        reindex(from: index)
        removed
    }

    /**
     * Removes `key`'s entry and moves the last one into its place. O(1), but the order changes.
     *
     * @return the value removed
     */
    public func swapRemove(key: K): ?V {
        let index = indices.remove(key) ?? return None
        let (_, removed) = entries[index]
        // read before removing, as in `shiftRemove`
        let last = entries[entries.size - 1]
        entries.remove(at: entries.size - 1)
        if (index < entries.size) {
            entries[index] = last
            indices[last[0]] = index
        }
        removed
    }

    /**
     * Keeps the order of the rest. If `predicate` throws, the map is left as it was.
     */
    public func removeIf(predicate: (K, V) -> Bool): Unit {
        let kept = entries.filter {entry => !predicate(entry[0], entry[1])}
        if (kept.size == entries.size) {
            return
        }
        entries.clear()
        entries.add(all: kept)
        indices.clear()
        reindex(from: 0)
    }

    public func clear(): Unit {
        entries.clear()
        indices.clear()
    }

    public func entryView(key: K): MapEntryView<K, V> {
        EntryView(this, key)
    }

    public func clone(): IndexMap<K, V> {
        IndexMap(entries.clone(), indices.clone())
    }

    /**
     * Makes room for `additional` more entries without growing.
     */
    public func reserve(additional: Int64): Unit {
        entries.reserve(additional)
        indices.reserve(additional)
    }

    public func toArray(): Array<(K, V)> {
        entries.toArray()
    }

    private func reindex(from!: Int64): Unit {
        for (index in from..entries.size) {
            indices[entries[index][0]] = index
        }
    }
}

extend<K, V> IndexMap<K, V> <: ToString where K <: Hashable & Equatable<K> & ToString, V <: ToString {
    /**
     * As `HashMap` renders: `[(k, v), (k, v)]`, in order.
     */
    public func toString(): String {
        let rendered = entries.map {entry => "(${entry[0]}, ${entry[1]})"}
        "[${String.join(rendered.toArray(), delimiter: ", ")}]"
    }
}

class Keys<K, V> <: EquatableCollection<K> where K <: Hashable & Equatable<K> {
    Keys(private let map: IndexMap<K, V>) {}

    public prop size: Int64 {
        get() {
            map.size
        }
    }

    public func isEmpty(): Bool {
        map.isEmpty()
    }

    public func iterator(): Iterator<K> {
        map.entries.iterator().map {entry => entry[0]}
    }

    public func contains(element: K): Bool {
        map.contains(element)
    }

    public func contains(all!: Collection<K>): Bool {
        map.contains(all: all)
    }
}

class Values<K, V> <: Collection<V> where K <: Hashable & Equatable<K> {
    Values(private let map: IndexMap<K, V>) {}

    public prop size: Int64 {
        get() {
            map.size
        }
    }

    public func isEmpty(): Bool {
        map.isEmpty()
    }

    public func iterator(): Iterator<V> {
        map.entries.iterator().map {entry => entry[1]}
    }
}

/**
 * Setting `value` to `None` removes the entry, keeping the order of the rest.
 */
class EntryView<K, V> <: MapEntryView<K, V> where K <: Hashable & Equatable<K> {
    EntryView(private let map: IndexMap<K, V>, private let of: K) {}

    public prop key: K {
        get() {
            of
        }
    }

    public mut prop value: ?V {
        get() {
            map.get(of)
        }
        set(value) {
            match (value) {
                case Some(value) => map.add(of, value)
                case None => map.remove(of)
            }
        }
    }
}
