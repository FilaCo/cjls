package loupe.db

import std.unittest.*
import std.unittest.testmacro.*
import rope.Rope
import loupe.vfs.FileId

const BENCH_FILE_COUNT = 1000

const BENCH_READERS = 4

const BENCH_READS_PER_READER = 1000

let BENCH_DB = AnalysisDatabase()

let BENCH_FILES = Array<SourceFile>(BENCH_FILE_COUNT) {i => SourceFile(BENCH_DB, FileId(i), Rope())}

let BENCH_TABLE = {=>
    let files = Files()
    for (file in BENCH_FILES) {
        files.add(file.fileId(BENCH_DB), file)
    }
    files
}()

let BENCH_MISSING = FileId(BENCH_FILE_COUNT)

/**
 * The table of inputs a database shares with its snapshots: every query reaching a file reads it,
 * from whichever thread its handler runs on. `cjpm bench '--filter=FilesBench.*'`.
 */
@Test
class FilesBench {
    @Bench
    func getAFileThere(): ?SourceFile {
        BENCH_TABLE.get(FileId(BENCH_FILE_COUNT / 2))
    }

    @Bench
    func getAFileNeverSet(): ?SourceFile {
        BENCH_TABLE.get(BENCH_MISSING)
    }

    @Bench
    func addAFileAgain(): Unit {
        BENCH_TABLE.add(FileId(0), BENCH_FILES[0])
    }

    /**
     * Snapshots read at once, as handlers off the read loop do: `BENCH_READERS` threads, each
     * reading `BENCH_READS_PER_READER` files.
     */
    @Bench
    func getFromSeveralThreads(): Int64 {
        let readers = Array(BENCH_READERS) {
            reader => spawn {
                var found = 0
                for (i in 0..BENCH_READS_PER_READER) {
                    if (BENCH_TABLE.get(FileId((i + reader) % BENCH_FILE_COUNT)).isSome()) {
                        found++
                    }
                }
                found
            }
        }
        readers.iterator().fold(0) {sum, reader => sum + reader.get()}
    }
}
