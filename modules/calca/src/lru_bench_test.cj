package calca

import std.unittest.*
import std.unittest.testmacro.*
import calca.macros.*

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
 * A fetch that hits, with and without `lru`: what touching the key costs. The first batch computes,
 * the warm-up absorbs it. `cjpm bench '--filter=LruFetchBench.*'`.
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
