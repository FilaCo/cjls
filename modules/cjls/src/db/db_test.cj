package cjls.db

import std.collection.collectArray
import std.sync.*
import std.unittest.*
import std.unittest.testmacro.*
import calca.*
import calca.macros.*
import rope.Rope
import cjls.vfs.*

let itemCountRuns = AtomicInt64(0)

/**
 * A query reading the tree, counting how often it runs.
 */
@CalcaTracked
func itemCount(db: SourceDatabase, file: SourceFile): Int64 {
    itemCountRuns.fetchAdd(1)
    collectArray(parse(db, file).syntaxNode().children()).size
}

@Test
class BaseDbTest {
    @TestCase
    func aFileIsParsedOnceUntilItChanges() {
        // arrange
        let db = RootDatabase()
        let file = db.setFileText(FileId(0), Rope("func f() {}\n"))
        let first = parse(db, file)

        // act
        let again = parse(db, file)
        db.setFileText(FileId(0), Rope("func f() {}\nfunc g() {}\n"))
        let changed = parse(db, file)

        // assert
        @Expect(refEq(first, again))
        @Expect(first.errors.size, 0)
        @Expect(changed.syntaxNode().text(), "func f() {}\nfunc g() {}\n")
    }

    @TestCase
    func aTextThatParsesTheSameLeavesWhatReadTheTreeAlone() {
        // arrange
        let db = RootDatabase()
        let file = db.setFileText(FileId(0), Rope("let x = 1\n"))
        @Expect(itemCount(db, file), 1)
        let runs = itemCountRuns.load()

        // act
        db.setFileText(FileId(0), Rope("let x = 1\n"))
        let count = itemCount(db, file)

        // assert
        @Expect(count, 1)
        @Expect(itemCountRuns.load(), runs)
    }

    @TestCase
    func aFileKeepsItsInputWhateverItsTextBecomes() {
        // arrange
        let db = RootDatabase()
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
        let db = RootDatabase()
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
        let db = RootDatabase()
        let file = db.setFileText(FileId(0), Rope("let x = 1\n"))
        let snapshot = db.snapshot()
        @Expect(file.text(snapshot).toString(), "let x = 1\n")

        // act
        db.setFileText(FileId(0), Rope("let y = 2\n"))

        // assert
        @AssertThrows[Cancelled](parse(snapshot, file))
        @Expect(file.text(db.snapshot()).toString(), "let y = 2\n")
    }

    @TestCase
    func aSnapshotCannotSetAFile() {
        // arrange
        let db = RootDatabase()
        db.setFileText(FileId(0), Rope("a"))

        // act, assert
        @AssertThrows[IllegalStateException](db.snapshot().setFileText(FileId(0), Rope("b")))
        @AssertThrows[IllegalStateException](db.snapshot().setFileText(FileId(1), Rope("b")))
    }
}
