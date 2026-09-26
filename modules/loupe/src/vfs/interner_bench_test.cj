package loupe.vfs

import std.collection.*
import std.collection.concurrent.ConcurrentHashMap
import std.sync.*
import std.unittest.*
import std.unittest.testmacro.*
import index_map.IndexSet
import index_map.concurrent.ConcurrentIndexSet

/**
 * One way to give paths dense ids from several threads, as `PathInterner` does.
 */
interface BenchInterner {
    func lookup(path: VfsPath): ?Int64

    func intern(path: VfsPath): Int64

    func path(id: Int64): ?VfsPath
}

/**
 * No lock at all: what the table itself costs. Safe only while nobody writes.
 */
class IndexSetAlone <: BenchInterner {
    let paths = IndexSet<VfsPath>()

    public func lookup(path: VfsPath): ?Int64 {
        paths.indexOf(path)
    }

    public func intern(path: VfsPath): Int64 {
        paths.addWithIndex(path)[0]
    }

    public func path(id: Int64): ?VfsPath {
        paths.getAt(id)
    }
}

class IndexSetUnderMutex <: BenchInterner {
    let paths = IndexSet<VfsPath>()
    let lock = Mutex()

    public func lookup(path: VfsPath): ?Int64 {
        synchronized(lock) {
            paths.indexOf(path)
        }
    }

    public func intern(path: VfsPath): Int64 {
        synchronized(lock) {
            paths.addWithIndex(path)[0]
        }
    }

    public func path(id: Int64): ?VfsPath {
        synchronized(lock) {
            paths.getAt(id)
        }
    }
}

// `PathInterner` before #26
class IndexSetUnderReadWriteLock <: BenchInterner {
    let paths = IndexSet<VfsPath>()
    let lock = ReadWriteLock()

    public func lookup(path: VfsPath): ?Int64 {
        synchronized(lock.readLock) {
            paths.indexOf(path)
        }
    }

    public func intern(path: VfsPath): Int64 {
        match (lookup(path)) {
            case Some(id) => id
            case None => synchronized(lock.writeLock) {
                paths.addWithIndex(path)[0]
            }
        }
    }

    public func path(id: Int64): ?VfsPath {
        synchronized(lock.readLock) {
            paths.getAt(id)
        }
    }
}

// `PathInterner` in #26, before `ConcurrentIndexSet`
class TwoConcurrentHashMaps <: BenchInterner {
    let ids = ConcurrentHashMap<VfsPath, Int64>()
    let paths = ConcurrentHashMap<Int64, VfsPath>()
    let lock = Mutex()
    var count = 0

    public func lookup(path: VfsPath): ?Int64 {
        ids.get(path)
    }

    public func intern(path: VfsPath): Int64 {
        match (ids.get(path)) {
            case Some(id) => id
            case None => synchronized(lock) {
                match (ids.get(path)) {
                    case Some(id) => id
                    case None =>
                        let id = count
                        paths.add(id, path)
                        ids.add(path, id)
                        count++
                        id
                }
            }
        }
    }

    public func path(id: Int64): ?VfsPath {
        paths.get(id)
    }
}

// `PathInterner` itself, on a `ConcurrentIndexSet`
class PathInternerAsIs <: BenchInterner {
    let interner = PathInterner()

    public func lookup(path: VfsPath): ?Int64 {
        match (interner.lookup(path)) {
            case Some(id) => id.index
            case None => None
        }
    }

    public func intern(path: VfsPath): Int64 {
        interner.intern(path).index
    }

    public func path(id: Int64): ?VfsPath {
        interner.path(FileId(id))
    }
}

class InternerVariant <: ToString {
    // holding `BENCH_INTERNED`
    let filled: BenchInterner

    InternerVariant(let name: String, let make: () -> BenchInterner, let shared!: Bool = true) {
        filled = make()
        for (path in BENCH_INTERNED) {
            filled.intern(path)
        }
    }

    public func toString(): String {
        name
    }
}

let INTERNER_VARIANTS = [
    InternerVariant("IndexSetAlone", {=> IndexSetAlone()}, shared: false),
    InternerVariant("IndexSetUnderMutex", {=> IndexSetUnderMutex()}),
    InternerVariant("IndexSetUnderReadWriteLock", {=> IndexSetUnderReadWriteLock()}),
    InternerVariant("TwoConcurrentHashMaps", {=> TwoConcurrentHashMaps()}),
    InternerVariant("PathInterner", {=> PathInternerAsIs()})
]

// the ones safe to write to while others read
let SHARED_INTERNER_VARIANTS = INTERNER_VARIANTS.filter {variant => variant.shared}

/**
 * Every way of interning paths, on the operations `PathInterner` does: which a shared interner
 * should be, and what `@Frozen` on `index_map` changes. `cjpm bench '--filter=InternerBench.*'`.
 */
@Test
class InternerBench {
    @Bench[variant in INTERNER_VARIANTS]
    func lookUpAPathSeen(variant: InternerVariant): ?Int64 {
        variant.filled.lookup(BENCH_INTERNED[BENCH_PATH_COUNT / 2])
    }

    @Bench[variant in INTERNER_VARIANTS]
    func lookUpAPathNeverSeen(variant: InternerVariant): ?Int64 {
        variant.filled.lookup(BENCH_UNSEEN)
    }

    @Bench[variant in INTERNER_VARIANTS]
    func internAPathSeen(variant: InternerVariant): Int64 {
        variant.filled.intern(BENCH_INTERNED[BENCH_PATH_COUNT / 2])
    }

    @Bench[variant in INTERNER_VARIANTS]
    func pathOfAnId(variant: InternerVariant): ?VfsPath {
        variant.filled.path(BENCH_PATH_COUNT / 2)
    }

    /**
     * A new interner given `BENCH_PATH_COUNT` paths, one thread.
     */
    @Bench[variant in INTERNER_VARIANTS]
    func internPathsNeverSeen(variant: InternerVariant): Int64 {
        let interner = variant.make()
        for (path in BENCH_INTERNED) {
            interner.intern(path)
        }
        interner.lookup(BENCH_INTERNED[0]).getOrThrow()
    }

    /**
     * `BENCH_READERS` threads looking up `BENCH_READS_PER_READER` paths each at once.
     */
    @Bench[variant in INTERNER_VARIANTS]
    func lookUpFromSeveralThreads(variant: InternerVariant): Int64 {
        let interner = variant.filled
        let readers = Array(BENCH_READERS) {
            reader => spawn {
                var found = 0
                for (i in 0..BENCH_READS_PER_READER) {
                    if (interner.lookup(BENCH_INTERNED[(i + reader) % BENCH_PATH_COUNT]).isSome()) {
                        found++
                    }
                }
                found
            }
        }
        readers.iterator().fold(0) {sum, reader => sum + reader.get()}
    }

    /**
     * A new interner given `BENCH_PATH_COUNT` paths by one thread while `BENCH_READERS` others look
     * them up: the writer and the readers contend, as a message interning a new document does with
     * the snapshots answering others.
     */
    @Bench[variant in SHARED_INTERNER_VARIANTS]
    func internWhileSeveralThreadsLookUp(variant: InternerVariant): Int64 {
        let interner = variant.make()
        let readers = Array(BENCH_READERS) {
            reader => spawn {
                var found = 0
                for (i in 0..BENCH_READS_PER_READER) {
                    if (interner.lookup(BENCH_INTERNED[(i + reader) % BENCH_PATH_COUNT]).isSome()) {
                        found++
                    }
                }
                found
            }
        }
        for (path in BENCH_INTERNED) {
            interner.intern(path)
        }
        readers.iterator().fold(0) {sum, reader => sum + reader.get()}
    }
}

let BENCH_INT_SET = IndexSet<Int64>(Array(BENCH_PATH_COUNT) {i => i})

let BENCH_INT_MAP = HashMap<Int64, Int64>((0..BENCH_PATH_COUNT).iterator().map {i => (i, i)} |> collectArray)

let BENCH_INT_CONCURRENT_SET = {=>
    let set = ConcurrentIndexSet<Int64>()
    for (i in 0..BENCH_PATH_COUNT) {
        set.add(i)
    }
    set
}()

let BENCH_INT_CONCURRENT_MAP = {=>
    let map = ConcurrentHashMap<Int64, Int64>()
    for (i in 0..BENCH_PATH_COUNT) {
        map.add(i, i)
    }
    map
}()

let BENCH_PATH_SET = IndexSet<VfsPath>(BENCH_INTERNED)

let BENCH_PATH_MAP = HashMap<VfsPath, Int64>(BENCH_INTERNED.iterator().enumerate().map {entry => (entry[1], entry[0])} |> collectArray)

let BENCH_PATH_CONCURRENT_SET = {=>
    let set = ConcurrentIndexSet<VfsPath>()
    for (path in BENCH_INTERNED) {
        set.add(path)
    }
    set
}()

/**
 * One call into `index_map` from another package, no interface in between, against the std map it
 * wraps: what `@Frozen` saves (#28). `cjpm bench '--filter=IndexSetCallBench.*'`.
 */
@Test
class IndexSetCallBench {
    @Bench
    func indexSetOfIntsIndexOf(): ?Int64 {
        BENCH_INT_SET.indexOf(BENCH_PATH_COUNT / 2)
    }

    @Bench
    func indexSetOfIntsGetAt(): ?Int64 {
        BENCH_INT_SET.getAt(BENCH_PATH_COUNT / 2)
    }

    @Bench
    func concurrentIndexSetOfIntsIndexOf(): ?Int64 {
        BENCH_INT_CONCURRENT_SET.indexOf(BENCH_PATH_COUNT / 2)
    }

    @Bench
    func concurrentIndexSetOfIntsGetAt(): ?Int64 {
        BENCH_INT_CONCURRENT_SET.getAt(BENCH_PATH_COUNT / 2)
    }

    @Bench
    func hashMapOfIntsGet(): ?Int64 {
        BENCH_INT_MAP.get(BENCH_PATH_COUNT / 2)
    }

    @Bench
    func concurrentHashMapOfIntsGet(): ?Int64 {
        BENCH_INT_CONCURRENT_MAP.get(BENCH_PATH_COUNT / 2)
    }

    @Bench
    func indexSetOfPathsIndexOf(): ?Int64 {
        BENCH_PATH_SET.indexOf(BENCH_INTERNED[BENCH_PATH_COUNT / 2])
    }

    @Bench
    func concurrentIndexSetOfPathsIndexOf(): ?Int64 {
        BENCH_PATH_CONCURRENT_SET.indexOf(BENCH_INTERNED[BENCH_PATH_COUNT / 2])
    }

    @Bench
    func hashMapOfPathsGet(): ?Int64 {
        BENCH_PATH_MAP.get(BENCH_INTERNED[BENCH_PATH_COUNT / 2])
    }
}
