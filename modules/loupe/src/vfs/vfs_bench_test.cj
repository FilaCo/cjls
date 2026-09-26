package loupe.vfs

import std.env.getTempDirectory
import std.unittest.*
import std.unittest.testmacro.*

const BENCH_PATH_COUNT = 1000

const BENCH_READERS = 4

const BENCH_READS_PER_READER = 1000

let BENCH_INTERNED = Array<VfsPath>(BENCH_PATH_COUNT) {
    i => VfsPath.file(getTempDirectory().join("src/file_${i}.cj").toString())
}

let BENCH_INTERNER = {=>
    let interner = PathInterner()
    for (path in BENCH_INTERNED) {
        interner.intern(path)
    }
    interner
}()

let BENCH_UNSEEN = VfsPath.file(getTempDirectory().join("src/unseen.cj").toString())

let BENCH_ID = FileId(BENCH_PATH_COUNT / 2)

/**
 * The ids of paths, shared by the server and its snapshots: a message looks up the path of every
 * document it names, an answer turns ids back into paths, from whichever thread its handler runs
 * on. `cjpm bench '--filter=PathInternerBench.*'`.
 */
@Test
class PathInternerBench {
    @Bench
    func lookUpAPathSeen(): ?FileId {
        BENCH_INTERNER.lookup(BENCH_INTERNED[BENCH_PATH_COUNT / 2])
    }

    @Bench
    func lookUpAPathNeverSeen(): ?FileId {
        BENCH_INTERNER.lookup(BENCH_UNSEEN)
    }

    @Bench
    func internAPathSeen(): FileId {
        BENCH_INTERNER.intern(BENCH_INTERNED[BENCH_PATH_COUNT / 2])
    }

    @Bench
    func pathOfAnId(): VfsPath {
        BENCH_INTERNER.path(BENCH_ID)
    }

    /**
     * Snapshots looking paths up at once, as handlers off the read loop do: `BENCH_READERS`
     * threads, each looking up `BENCH_READS_PER_READER` paths.
     */
    @Bench
    func lookUpFromSeveralThreads(): Int64 {
        let readers = Array(BENCH_READERS) {
            reader => spawn {
                var found = 0
                for (i in 0..BENCH_READS_PER_READER) {
                    if (BENCH_INTERNER.lookup(BENCH_INTERNED[(i + reader) % BENCH_PATH_COUNT]).isSome()) {
                        found++
                    }
                }
                found
            }
        }
        readers.iterator().fold(0) {sum, reader => sum + reader.get()}
    }
}
