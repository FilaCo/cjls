package loupe.db

import std.sync.*
import std.unittest.*
import std.unittest.testmacro.*
import calca.*
import calca.macros.*
import rope.Rope
import loupe.vfs.*

let lineCountRuns = AtomicInt64(0)

/**
 * A query of the kind every layer above writes, taking the database itself; it counts its runs.
 */
@CalcaTracked
func lineCount(db: AnalysisDatabase, file: SourceFile): Int64 {
    lineCountRuns.fetchAdd(1)
    file.text(db).lineCount
}

@Test
class DbTest {
    @TestCase
    func aQueryRunsAgainOnlyOnceItsFileChanges() {
        // arrange
        let db = AnalysisDatabase()
        let file = db.setFileText(FileId(0), Rope("a\n"))
        @Expect(lineCount(db, file), 2)
        let runs = lineCountRuns.load()

        // act
        let unchanged = lineCount(db, file)
        let ranAgain = lineCountRuns.load() - runs
        db.setFileText(FileId(0), Rope("a\nb\n"))
        let changed = lineCount(db, file)

        // assert
        @Expect(unchanged, 2)
        @Expect(ranAgain, 0)
        @Expect(changed, 3)
    }

    @TestCase
    func aFileKeepsItsInputWhateverItsTextBecomes() {
        // arrange
        let db = AnalysisDatabase()
        let file = db.setFileText(FileId(3), Rope("a"))

        // act
        let again = db.setFileText(FileId(3), Rope("b"))

        // assert
        @Expect(again, file)
        @Expect(db.sourceFile(FileId(3)), Some(file))
        @Expect(db.sourceFile(FileId(4)), None<SourceFile>)
        @Expect(file.text(db).toString(), "b")
    }

    @TestCase
    func changesFromTheVfsReachTheFiles() {
        // arrange
        let vfs = Vfs()
        let db = AnalysisDatabase()
        let a = VfsPath.file("/a.cj")
        let b = VfsPath.file("/b.cj")
        vfs.setFileContents(a, Rope("a"))
        vfs.setFileContents(b, Rope("b"))
        db.applyChanges(vfs, vfs.takeChanges())
        let fileA = db.sourceFile(vfs.fileId(a).getOrThrow()).getOrThrow()
        let fileB = db.sourceFile(vfs.fileId(b).getOrThrow()).getOrThrow()

        // act
        vfs.setFileContents(a, Rope("a2"))
        vfs.setFileContents(b, None)
        db.applyChanges(vfs, vfs.takeChanges())

        // assert
        @Expect(fileA.text(db).toString(), "a2")
        @Expect(fileB.text(db).toString(), "")
    }

    @TestCase
    func aSnapshotSeesItsRevisionAndIsCancelledOnceItIsGone() {
        // arrange
        let db = AnalysisDatabase()
        let file = db.setFileText(FileId(0), Rope("let x = 1\n"))
        let snapshot = db.snapshot()
        @Expect(file.text(snapshot).toString(), "let x = 1\n")

        // act
        db.setFileText(FileId(0), Rope("let y = 2\n"))

        // assert
        @AssertThrows[Cancelled](lineCount(snapshot, file))
        @Expect(file.text(db.snapshot()).toString(), "let y = 2\n")
    }

    @TestCase
    func aSnapshotCannotSetAFile() {
        // arrange
        let db = AnalysisDatabase()
        db.setFileText(FileId(0), Rope("a"))

        // act, assert
        @AssertThrows[IllegalStateException](db.snapshot().setFileText(FileId(0), Rope("b")))
        @AssertThrows[IllegalStateException](db.snapshot().setFileText(FileId(1), Rope("b")))
    }
}
