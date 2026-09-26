package index_map

import std.collection.*

/**
 * A hash set that keeps its elements in the order they were first added, the way Rust's `indexmap`
 * does, and so gives each one an index: its position in that order. An `IndexMap` of the elements
 * to nothing, as there.
 *
 * Adding an element already there keeps it where it is. Removing one either shifts every later
 * element down a place (`shiftRemove`, and `remove`: O(n), the order of the rest kept) or moves the
 * last element into the gap (`swapRemove`: O(1)). Iteration follows the order.
 *
 * Not thread-safe, as `HashSet` is not.
 */
public class IndexSet<T> <: Set<T> where T <: Hashable & Equatable<T> {
    private IndexSet(let map: IndexMap<T, Unit>) {}

    public init() {
        this(IndexMap<T, Unit>())
    }

    /**
     * @throws IllegalArgumentException - if `capacity` is negative
     */
    public init(capacity: Int64) {
        this(IndexMap<T, Unit>(capacity))
    }

    /**
     * In the order of `elements`; an element met again keeps its first place.
     */
    public init(elements: Collection<T>) {
        this(elements.size)
        add(all: elements)
    }

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

    public func iterator(): Iterator<T> {
        map.keys().iterator()
    }

    @Frozen
    public func contains(element: T): Bool {
        map.contains(element)
    }

    public func contains(all!: Collection<T>): Bool {
        map.contains(all: all)
    }

    /**
     * Whether every element of this set is in `other`, whatever the order.
     */
    public func subsetOf(other: ReadOnlySet<T>): Bool {
        size <= other.size && iterator().all {element => other.contains(element)}
    }

    /**
     * The position of `element`.
     */
    @Frozen
    public func indexOf(element: T): ?Int64 {
        map.indexOf(element)
    }

    /**
     * The element at `index`, or `None` if there is none there.
     */
    @Frozen
    public func getAt(index: Int64): ?T {
        // a `match`, not `Option.map`, as in `IndexMap.get`
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
    @Frozen
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
        let (index, replaced) = map.addWithIndex(element, ())
        (index, replaced.isNone())
    }

    public func add(all!: Collection<T>): Unit {
        all.iterator().forEach {element => add(element)}
    }

    /**
     * As `shiftRemove`: the order of the rest is kept.
     */
    public func remove(element: T): Bool {
        shiftRemove(element)
    }

    public func remove(all!: Collection<T>): Unit {
        map.remove(all: all)
    }

    /**
     * Removes `element` and shifts every later one down a place. O(n).
     *
     * @return whether it was there
     */
    public func shiftRemove(element: T): Bool {
        map.shiftRemove(element).isSome()
    }

    /**
     * Removes `element` and moves the last one into its place. O(1), but the order changes.
     *
     * @return whether it was there
     */
    public func swapRemove(element: T): Bool {
        map.swapRemove(element).isSome()
    }

    /**
     * Keeps the order of the rest. If `predicate` throws, the set is left as it was.
     */
    public func removeIf(predicate: (T) -> Bool): Unit {
        map.removeIf {element, _ => predicate(element)}
    }

    /**
     * Keeps only the elements also in `all`, in their order.
     */
    public func retain(all!: Set<T>): Unit {
        removeIf {element => !all.contains(element)}
    }

    public func clear(): Unit {
        map.clear()
    }

    public func clone(): IndexSet<T> {
        IndexSet(map.clone())
    }

    /**
     * Makes room for `additional` more elements without growing.
     */
    public func reserve(additional: Int64): Unit {
        map.reserve(additional)
    }

    public func toArray(): Array<T> {
        map.keys().toArray()
    }
}

extend<T> IndexSet<T> <: ToString where T <: Hashable & Equatable<T> & ToString {
    /**
     * As `HashSet` renders: `[a, b]`, in order.
     */
    public func toString(): String {
        "[${iterator() |> collectString(delimiter: ", ")}]"
    }
}
