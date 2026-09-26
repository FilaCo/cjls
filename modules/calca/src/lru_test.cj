package calca

import std.unittest.*
import std.unittest.testmacro.*
import calca.macros.*

@CalcaTracked[lru: 1]
func lruLength(db: TestDb, file: SourceFile): Int64 {
    db.log("lruLength(${file})")
    file.text(db).size
}

@CalcaTracked
func doubledLruLength(db: TestDb, file: SourceFile): Int64 {
    db.log("doubledLruLength(${file})")
    lruLength(db, file) * 2
}

@CalcaTracked[lru: 2]
func lru2Length(db: TestDb, file: SourceFile): Int64 {
    db.log("lru2Length(${file})")
    file.text(db).size
}

@CalcaTracked[lru: 1]
func lruLineCount(db: TestDb, file: SourceFile): Int64 {
    db.log("lruLineCount(${file})")
    file.text(db).split("\n").size
}

@CalcaTracked
func afterLruLineCount(db: TestDb, file: SourceFile): Int64 {
    db.log("afterLruLineCount(${file})")
    lruLineCount(db, file)
}

@CalcaTracked
func lineCount(db: TestDb, file: SourceFile): Int64 {
    db.log("lineCount(${file})")
    file.text(db).split("\n").size
}

@CalcaTracked
func afterLineCount(db: TestDb, file: SourceFile): Int64 {
    db.log("afterLineCount(${file})")
    lineCount(db, file)
}

@CalcaTracked[noEq, lru: 1]
func lruLengthNoEq(db: TestDb, file: SourceFile): Int64 {
    db.log("lruLengthNoEq(${file})")
    file.text(db).size
}

@Test
class LruTest {
    @TestCase
    func anEvictedValueIsComputedAgainWhenFetched(): Unit {
        // arrange
        let db = TestDatabase()
        let (a, b, other) = files(db)
        lruLength(db, a)
        lruLength(db, b)
        other.setText(db).to("changed")
        db.events.take()

        // act
        let result = lruLength(db, a)

        // assert
        @Expect(result, 5)
        @Expect(db.events.take(), ["lruLength(SourceFile(0))"])
    }

    @TestCase
    func anEvictedValueIsVerifiedWithoutBeingComputed(): Unit {
        // arrange
        let db = TestDatabase()
        let (a, b, other) = files(db)
        doubledLruLength(db, a)
        lruLength(db, b)
        other.setText(db).to("changed")
        db.events.take()

        // act
        let result = doubledLruLength(db, a)

        // assert
        @Expect(result, 10)
        @Expect(db.events.take().size, 0)
    }

    @TestCase
    func anEvictedValueWhoseInputChangedIsComputedOnlyByWhoeverFetchesIt(): Unit {
        // arrange
        let db = TestDatabase()
        let (a, b, _) = files(db)
        doubledLruLength(db, a)
        lruLength(db, b)
        a.setText(db).to("hello, world")
        db.events.take()

        // act
        let result = doubledLruLength(db, a)

        // assert
        @Expect(result, 24)
        @Expect(db.events.take(), ["doubledLruLength(SourceFile(0))", "lruLength(SourceFile(0))"])
    }

    @TestCase
    func anEvictedValueComputedAgainAfterAChangeIsNotBackdated(): Unit {
        // arrange
        let db = TestDatabase()
        let a = SourceFile(db, "a.cj", "a\nb")
        let b = SourceFile(db, "b.cj", "")
        afterLruLineCount(db, a)
        lruLineCount(db, b)
        a.setText(db).to("c\nd")
        db.events.take()

        // act
        afterLruLineCount(db, a)

        // assert
        @Expect(db.events.take(), ["afterLruLineCount(SourceFile(0))", "lruLineCount(SourceFile(0))"])
    }

    @TestCase
    func aValueKeptAndComputedAgainAfterAChangeIsBackdated(): Unit {
        // arrange
        let db = TestDatabase()
        let a = SourceFile(db, "a.cj", "a\nb")
        let b = SourceFile(db, "b.cj", "")
        afterLineCount(db, a)
        lineCount(db, b)
        a.setText(db).to("c\nd")
        db.events.take()

        // act
        afterLineCount(db, a)

        // assert
        @Expect(db.events.take(), ["lineCount(SourceFile(0))"])
    }

    @TestCase
    func nothingIsEvictedWhileASnapshotReads(): Unit {
        // arrange
        let db = TestDatabase()
        let (a, b, other) = files(db)
        let snapshot = db.snapshot()

        // act
        lruLength(snapshot, a)
        lruLength(snapshot, b)
        lruLength(snapshot, a)
        let whileReading = db.events.take()
        other.setText(db).to("changed")
        lruLength(db, a)
        lruLength(db, b)

        // assert
        @Expect(whileReading, ["lruLength(SourceFile(0))", "lruLength(SourceFile(1))"])
        @Expect(db.events.take(), ["lruLength(SourceFile(1))"])
    }

    @TestCase
    func aValueRememberedIsUsedWhenFetched(): Unit {
        // arrange
        let db = TestDatabase()
        let (a, b, other) = files(db)
        let c = SourceFile(db, "c.cj", "c")
        lru2Length(db, a)
        lru2Length(db, b)
        lru2Length(db, a)
        lru2Length(db, c)
        other.setText(db).to("changed")
        db.events.take()

        // act
        lru2Length(db, a)
        lru2Length(db, c)
        lru2Length(db, b)

        // assert
        @Expect(db.events.take(), ["lru2Length(SourceFile(1))"])
    }

    @TestCase
    func verifyingAValueForAnotherIsNotAUse(): Unit {
        // arrange
        let db = TestDatabase()
        let (a, b, other) = files(db)
        doubledLruLength(db, a)
        lruLength(db, b)
        other.setText(db).to("changed")
        doubledLruLength(db, a)
        other.setText(db).to("changed again")
        db.events.take()

        // act
        lruLength(db, b)
        lruLength(db, a)

        // assert
        @Expect(db.events.take(), ["lruLength(SourceFile(0))"])
    }

    @TestCase
    func theCapacityIsTheNumberOfValuesKept(): Unit {
        // arrange
        let db = TestDatabase()
        let (a, b, other) = files(db)
        let c = SourceFile(db, "c.cj", "c")
        lru2Length(db, a)
        lru2Length(db, b)
        lru2Length(db, c)
        other.setText(db).to("changed")
        db.events.take()

        // act
        lru2Length(db, b)
        lru2Length(db, c)
        lru2Length(db, a)

        // assert
        @Expect(db.events.take(), ["lru2Length(SourceFile(0))"])
    }

    @TestCase
    func lruGoesTogetherWithNoEq(): Unit {
        // arrange
        let db = TestDatabase()
        let (a, b, other) = files(db)
        lruLengthNoEq(db, a)
        lruLengthNoEq(db, b)
        other.setText(db).to("changed")
        db.events.take()

        // act
        lruLengthNoEq(db, b)
        lruLengthNoEq(db, a)

        // assert
        @Expect(db.events.take(), ["lruLengthNoEq(SourceFile(0))"])
    }

    /**
     * `a` and `b`, which the queries read, and `other`, which none does: setting it opens a revision.
     */
    private func files(db: TestDatabase): (SourceFile, SourceFile, SourceFile) {
        (SourceFile(db, "a.cj", "hello"), SourceFile(db, "b.cj", "hi"), SourceFile(db, "other.cj", ""))
    }
}
