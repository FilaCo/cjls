package calca

import std.unittest.*
import std.unittest.testmacro.*
import calca.macros.*

/**
 * Collected once unused for one active revision.
 */
@CalcaInterned[revisions: 1]
struct Word {
    let text: String
}

/**
 * Collected once unused for the default 3.
 */
@CalcaInterned
struct Term {
    let text: String
}

@CalcaInterned[forever]
struct Keyword {
    let text: String
}

/**
 * Interns the file's text and never reads it.
 */
@CalcaTracked
func wordOf(db: TestDb, file: SourceFile): Word {
    db.log("wordOf(${file})")
    Word(db, file.text(db))
}

@CalcaTracked
func wordsOf(db: TestDb, file: SourceFile): Array<Word> {
    file.text(db).split(" ").map {text => Word(db, text)}
}

@CalcaTracked
func wordLength(db: TestDb, word: Word): Int64 {
    db.log("wordLength(${word})")
    word.text(db).size
}

@CalcaTracked
func lengthOfWord(db: TestDb, file: SourceFile): Int64 {
    db.log("lengthOfWord(${file})")
    wordLength(db, Word(db, file.text(db)))
}

@CalcaTracked
func termOf(db: TestDb, file: SourceFile): Term {
    Term(db, file.text(db))
}

@CalcaTracked
func keywordOf(db: TestDb, file: SourceFile): Keyword {
    Keyword(db, file.text(db))
}

@Test
class InternedGcTest {
    @TestCase
    func aValueUnusedIsCollectedAndItsSlotReusedUnderTheNextGeneration(): Unit {
        // arrange
        let db = TestDatabase()
        let (a, other) = files(db, "foo")
        let foo = wordOf(db, a)
        activeRevisions(db, other, 1)
        other.setText(db).to("collects")

        // act
        let bar = Word(db, "bar")

        // assert
        @Expect(foo.toString(), "Word(0)")
        @Expect(bar.toString(), "Word(0g1)")
        @AssertThrows[IllegalStateException](foo.text(db))
    }

    @TestCase
    func aQueryThatOnlyInternsIsComputedAgainOnceItsValueIsCollected(): Unit {
        // arrange
        let db = TestDatabase()
        let (a, other) = files(db, "foo")
        let foo = wordOf(db, a)
        activeRevisions(db, other, 2)
        db.events.take()

        // act
        let again = wordOf(db, a)

        // assert
        @Expect(db.events.take(), ["wordOf(SourceFile(0))"])
        @Expect(again != foo)
        @Expect(again.text(db), "foo")
    }

    @TestCase
    func verifyingTheQueryThatInternedAValueKeepsItAlive(): Unit {
        // arrange
        let db = TestDatabase()
        let (a, other) = files(db, "foo")
        let foo = wordOf(db, a)
        db.events.take()

        // act
        for (i in 0..3) {
            other.setText(db).to("${i}")
            wordOf(db, other)
            @Expect(wordOf(db, a), foo)
        }

        // assert
        @Expect(db.events.take(), ["wordOf(SourceFile(1))", "wordOf(SourceFile(1))", "wordOf(SourceFile(1))"])
        @Expect(foo.text(db), "foo")
    }

    @TestCase
    func aValueInternedByAMoreDurableQueryIsNeverCollected(): Unit {
        // arrange
        let db = TestDatabase()
        let (m, other) = files(db, "")
        m.setText(db).withDurability(Durability.Medium).to("x")
        let x = wordOf(db, m)
        activeRevisions(db, other, 3)
        db.events.take()

        // act
        let again = wordOf(db, m)

        // assert
        @Expect(db.events.take().size, 0)
        @Expect(again, x)
        @Expect(x.text(db), "x")
    }

    @TestCase
    func aValueInternedOutsideAnyQueryIsNeverCollected(): Unit {
        // arrange
        let db = TestDatabase()
        let (_, other) = files(db, "")
        let x = Word(db, "x")

        // act
        activeRevisions(db, other, 3)

        // assert
        @Expect(x.text(db), "x")
    }

    @TestCase
    func revisionsTheTableIsNotUsedInDoNotAgeItsValues(): Unit {
        // arrange
        let db = TestDatabase()
        let (a, other) = files(db, "foo")
        let foo = wordOf(db, a)

        // act
        for (i in 0..6) {
            other.setText(db).to("${i}")
        }

        // assert
        @Expect(foo.text(db), "foo")
    }

    @TestCase
    func aValueLivesAsManyActiveRevisionsAsItsTypeSays(): Unit {
        // arrange
        let db = TestDatabase()
        let (a, other) = files(db, "foo")
        let foo = termOf(db, a)

        // act
        activeRevisions(db, other, 2, use: {=> termOf(db, other)})
        other.setText(db).to("kept")
        // reading `foo` would use it: whether its slot is free tells instead
        let probe = Term(db, "probe")
        other.setText(db).to("collects")

        // assert
        @Expect(probe.toString(), "Term(3)")
        @AssertThrows[IllegalStateException](foo.text(db))
    }

    @TestCase
    func aValueOfATypeKeptForeverIsNeverCollected(): Unit {
        // arrange
        let db = TestDatabase()
        let (a, other) = files(db, "foo")
        let foo = keywordOf(db, a)

        // act
        activeRevisions(db, other, 3, use: {=> keywordOf(db, other)})

        // assert
        @Expect(foo.text(db), "foo")
    }

    @TestCase
    func aSlotReusedByOtherFieldsNeverAnswersForTheOldValue(): Unit {
        // arrange
        let db = TestDatabase()
        let (a, other) = files(db, "foo")
        @Expect(lengthOfWord(db, a), 3)
        activeRevisions(db, other, 1)
        other.setText(db).to("collects")
        let quux = Word(db, "quux")
        db.events.take()

        // act
        let result = lengthOfWord(db, a)

        // assert
        @Expect(quux.toString(), "Word(0g1)")
        @Expect(result, 3)
        @Expect(db.events.take(), ["lengthOfWord(SourceFile(0))", "wordLength(Word(2))"])
    }

    @TestCase
    func theSlotCollectedLastIsReusedFirst(): Unit {
        // arrange
        let db = TestDatabase()
        let (a, other) = files(db, "w0 w1 w2 w3 w4 w5")
        wordsOf(db, a)
        other.setText(db).to("w0 w1 w2 w4")
        wordsOf(db, other)
        other.setText(db).to("collects")

        // act
        let first = Word(db, "n1")
        let second = Word(db, "n2")

        // assert
        @Expect(first.toString(), "Word(5g1)")
        @Expect(second.toString(), "Word(3g1)")
    }

    @TestCase
    func snapshotsInterningTheSameFieldsAtOnceGetOneValue(): Unit {
        // arrange
        let db = TestDatabase()
        let files = Array<SourceFile>(8, {i => SourceFile(db, "${i}.cj", "same")})

        // act
        let snapshots = files.map {_ => db.snapshot()}
        let futures = Array<Future<Word>>(files.size, {i => spawn {wordOf(snapshots[i], files[i])}})
        let words = futures.map {future => future.get()}

        // assert
        @Expect(words.iterator().all {word => word == words[0]})
        @Expect(words[0].text(db), "same")
    }

    @TestCase
    func typingLeavesTheMemosOfOnlyTheWordsStillUsed(): Unit {
        // arrange
        let db = TestDatabase()
        let (typed, other) = files(db, "f")
        lengthOfWord(db, typed)

        // act
        typed.setText(db).to("fo")
        lengthOfWord(db, typed)
        typed.setText(db).to("foo")
        lengthOfWord(db, typed)
        other.setText(db).to("collects")
        lengthOfWord(db, typed)

        // assert
        let memos = wordLengthMemos(db)
        @Expect(memos.entries.size, 1)
        @Expect(memos.entries.slotCount, 2)
    }

    @TestCase
    func aMemoDroppedWithItsKeyIsChanged(): Unit {
        // arrange
        let db = TestDatabase()
        let (typed, other) = files(db, "f")
        lengthOfWord(db, typed)
        typed.setText(db).to("fo")
        lengthOfWord(db, typed)

        // act
        other.setText(db).to("collects")

        // assert
        @Expect(wordLengthMemos(db).maybeChangedAfter(db, Id(0), 0))
    }

    /**
     * `a`, holding `text`, and `other`, which the writes go to.
     */
    private func files(db: TestDatabase, text: String): (SourceFile, SourceFile) {
        (SourceFile(db, "a.cj", text), SourceFile(db, "other.cj", ""))
    }

    /**
     * `count` revisions, each with a write and a use of the table that uses no value interned
     * before.
     */
    private func activeRevisions(db: TestDatabase, other: SourceFile, count: Int64, use!: ?() -> Any = None): Unit {
        for (i in 0..count) {
            other.setText(db).to("active ${i}")
            match (use) {
                case Some(f) => f()
                case None => wordOf(db, other)
            }
        }
    }

    private func wordLengthMemos(db: TestDatabase): MemoTable<TestDb, Word, Int64> {
        let ingredient = db.storage.runtime.ingredientAt(CalcaTracked_wordLength.FUNCTION.index)
        (ingredient as MemoTable<TestDb, Word, Int64>).getOrThrow()
    }
}
