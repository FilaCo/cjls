package loupe.vfs

import std.env.getTempDirectory
import std.unittest.*
import std.unittest.testmacro.*

let BENCH_PATHS = ["src/main.cj", "проект/a b.cj", "src/./app/../lib.cj"].map {
    name => getTempDirectory().join(name).toString()
}

let BENCH_URIS = BENCH_PATHS.map {path => VfsPath.file(path).toUri()}

let BENCH_PAIR = (VfsPath.file(BENCH_PATHS[0]), VfsPath.file(BENCH_PATHS[1]))

/**
 * What every message pays for its document: a URI read in, a path looked up (hashed, compared),
 * and, for an answer, a URI written out. `cjpm bench '--filter=VfsPathBench.*'`.
 */
@Test
class VfsPathBench {
    @Bench[uri in BENCH_URIS]
    func fromUri(uri: String): VfsPath {
        VfsPath.fromUri(uri)
    }

    @Bench
    func fromAVirtualUri(): VfsPath {
        VfsPath.fromUri("untitled:Untitled-1")
    }

    @Bench[path in BENCH_PATHS]
    func file(path: String): VfsPath {
        VfsPath.file(path)
    }

    @Bench[path in BENCH_PATHS]
    func toUri(path: String): String {
        VfsPath.file(path).toUri()
    }

    @Bench
    func hashAndCompare(): Bool {
        let (a, b) = BENCH_PAIR
        a.hashCode() == b.hashCode() || a == b
    }
}
