package calca

import std.collection.*
import std.collection.concurrent.*
import std.sync.*
import std.unittest.*
import std.unittest.testmacro.*
import calca.macros.*

interface TestDb <: Database {
    func log(event: String): Unit

    /**
     * Blocks the query calling it until the test releases it.
     */
    func park(): Unit
}

/**
 * What the tracked functions below did, in order, shared by a database and its snapshots.
 */
class Events {
    private let lock = Mutex()
    private let events = ArrayList<String>()

    func add(event: String): Unit {
        synchronized(lock) {
            events.add(event)
        }
    }

    func take(): Array<String> {
        synchronized(lock) {
            let taken = events.toArray()
            events.clear()
            taken
        }
    }
}

/**
 * Where a query calling `park` waits: it says it is there on `parked`, and goes on once `released`.
 */
class Parking {
    let parked = LinkedBlockingQueue<Unit>(1)
    let released = LinkedBlockingQueue<Unit>(1)
}

class TestDatabase <: TestDb {
    private TestDatabase(private let storage_: Storage, let events: Events, let parking: Parking) {}

    init() {
        this(Storage(), Events(), Parking())
    }

    public prop storage: Storage {
        get() {
            storage_
        }
    }

    public func log(event: String): Unit {
        events.add(event)
    }

    public func park(): Unit {
        parking.parked.add(())
        parking.released.remove()
    }

    func snapshot(): TestDatabase {
        TestDatabase(storage_.snapshot(), events, parking)
    }
}

@CalcaInput
struct SourceFile {
    let path: String
    var text: String
}

@CalcaInput
struct Mode {
    var cyclic: Bool
}

@CalcaInterned
struct Name {
    let text: String
}

@CalcaInterned
struct Qualified {
    let pkg: String
    let name: Name
}

@CalcaTracked
func nameLength(db: TestDb, name: Name): Int64 {
    db.log("nameLength(${name})")
    name.text(db).size
}

@CalcaTracked
func firstWord(db: TestDb, file: SourceFile): Name {
    db.log("firstWord(${file})")
    Name(db, file.text(db).split(" ")[0])
}

@CalcaTracked
func firstWordLength(db: TestDb, file: SourceFile): Int64 {
    db.log("firstWordLength(${file})")
    nameLength(db, firstWord(db, file))
}

@CalcaTracked
func parkedLength(db: TestDb, file: SourceFile): Int64 {
    let text = file.text(db)
    db.park()
    file.path(db)
    text.size
}

@CalcaTracked
func length(db: TestDb, file: SourceFile): Int64 {
    db.log("length(${file})")
    file.text(db).size
}

@CalcaTracked
func isLong(db: TestDb, file: SourceFile): Bool {
    db.log("isLong(${file})")
    length(db, file) > 5
}

@CalcaTracked
func pathLength(db: TestDb, file: SourceFile): Int64 {
    db.log("pathLength(${file})")
    file.path(db).size
}

@CalcaTracked
func answer(db: TestDb): Int64 {
    db.log("answer")
    42
}

@CalcaTracked[noEq]
func lengthNoEq(db: TestDb, file: SourceFile): Int64 {
    db.log("lengthNoEq(${file})")
    file.text(db).size
}

@CalcaTracked
func afterNoEq(db: TestDb, file: SourceFile): Int64 {
    db.log("afterNoEq(${file})")
    lengthNoEq(db, file)
}

@CalcaTracked
func first(db: TestDb, mode: Mode): Int64 {
    second(db, mode) + 1
}

@CalcaTracked
func second(db: TestDb, mode: Mode): Int64 {
    if (mode.cyclic(db)) {
        first(db, mode)
    } else {
        0
    }
}

@CalcaTracked
func setsAnInput(db: TestDb, file: SourceFile): Int64 {
    match (db as TestDatabase) {
        case Some(writable) => file.setText(writable).to("")
        case None => ()
    }
    0
}

@Test
class CalcaTest {
    @TestCase
    func anInputGivesBackWhatItWasCreatedWith(): Unit {
        // arrange
        let db = TestDatabase()

        // act
        let file = SourceFile(db, "a.cj", "hello")

        // assert
        @Expect(file.path(db), "a.cj")
        @Expect(file.text(db), "hello")
        @Expect(file.toString(), "SourceFile(0)")
    }

    @TestCase
    func settingAFieldReturnsTheValueItReplaced(): Unit {
        // arrange
        let db = TestDatabase()
        let file = SourceFile(db, "a.cj", "hello")

        // act
        let old = file.setText(db).to("bye")

        // assert
        @Expect(old, "hello")
        @Expect(file.text(db), "bye")
    }

    @TestCase
    func inputsAreEqualByIdentityNotByValue(): Unit {
        // arrange
        let db = TestDatabase()

        // act
        let a = SourceFile(db, "a.cj", "")
        let b = SourceFile(db, "a.cj", "")

        // assert
        @Expect(a == a)
        @Expect(a != b)
    }

    @TestCase
    func aTrackedFunctionRunsOncePerArgumentInARevision(): Unit {
        // arrange
        let db = TestDatabase()
        let a = SourceFile(db, "a.cj", "hello")
        let b = SourceFile(db, "b.cj", "hi")

        // act
        let results = [length(db, a), length(db, a), length(db, b), length(db, b)]

        // assert
        @Expect(results, [5, 5, 2, 2])
        @Expect(db.events.take(), ["length(SourceFile(0))", "length(SourceFile(1))"])
    }

    @TestCase
    func aTrackedFunctionWithoutArgumentsIsRememberedToo(): Unit {
        // arrange
        let db = TestDatabase()

        // act
        let results = [answer(db), answer(db)]

        // assert
        @Expect(results, [42, 42])
        @Expect(db.events.take(), ["answer"])
    }

    @TestCase
    func changingWhatAFunctionReadRunsItAgain(): Unit {
        // arrange
        let db = TestDatabase()
        let file = SourceFile(db, "a.cj", "hello")
        length(db, file)
        db.events.take()

        // act
        file.setText(db).to("hello, world")
        let result = length(db, file)

        // assert
        @Expect(result, 12)
        @Expect(db.events.take(), ["length(SourceFile(0))"])
    }

    @TestCase
    func changingAFieldAFunctionDidNotReadLeavesItBe(): Unit {
        // arrange
        let db = TestDatabase()
        let file = SourceFile(db, "a.cj", "hello")
        pathLength(db, file)
        db.events.take()

        // act
        file.setText(db).to("hello, world")
        let result = pathLength(db, file)

        // assert
        @Expect(result, 4)
        @Expect(db.events.take().size, 0)
    }

    @TestCase
    func aChangeReachesAFunctionThroughAnother(): Unit {
        // arrange
        let db = TestDatabase()
        let file = SourceFile(db, "a.cj", "hi")
        @Expect(!isLong(db, file))
        db.events.take()

        // act
        file.setText(db).to("hello, world")
        let result = isLong(db, file)

        // assert
        @Expect(result)
        @Expect(db.events.take(), ["length(SourceFile(0))", "isLong(SourceFile(0))"])
    }

    @TestCase
    func aValueComputedAgainAsItWasDoesNotRunWhatReadIt(): Unit {
        // arrange
        let db = TestDatabase()
        let file = SourceFile(db, "a.cj", "hello")
        isLong(db, file)
        db.events.take()

        // act
        file.setText(db).to("world")
        let result = isLong(db, file)

        // assert
        @Expect(!result)
        @Expect(db.events.take(), ["length(SourceFile(0))"])
    }

    @TestCase
    func noEqCountsEveryComputationAsAChange(): Unit {
        // arrange
        let db = TestDatabase()
        let file = SourceFile(db, "a.cj", "hello")
        afterNoEq(db, file)
        db.events.take()

        // act
        file.setText(db).to("world")
        afterNoEq(db, file)

        // assert
        @Expect(db.events.take(), ["lengthNoEq(SourceFile(0))", "afterNoEq(SourceFile(0))"])
    }

    @TestCase
    func aDurableInputChangedIsStillSeen(): Unit {
        // arrange
        let db = TestDatabase()
        let library = SourceFile(db, "std.cj", "core", durability: Durability.High)
        let edited = SourceFile(db, "a.cj", "x")
        length(db, library)
        edited.setText(db).to("xy")
        @Expect(length(db, library), 4)
        db.events.take()

        // act
        library.setText(db).to("core, collections")
        let result = length(db, library)

        // assert
        @Expect(result, 17)
        @Expect(db.events.take(), ["length(SourceFile(0))"])
    }

    @TestCase
    func aFunctionNeedingItsOwnValueIsACycle(): Unit {
        // arrange
        let db = TestDatabase()
        let mode = Mode(db, true)

        // act
        let thrown = @AssertThrows[CycleException](first(db, mode))

        // assert
        @Expect(thrown.message, "cycle: first(0) -> second(0) -> first(0)")
    }

    @TestCase
    func aCycleFoundWhileVerifyingIsACycleToo(): Unit {
        // arrange
        let db = TestDatabase()
        let mode = Mode(db, false)
        @Expect(first(db, mode), 1)

        // act
        mode.setCyclic(db).to(true)

        // assert
        @AssertThrows[CycleException](first(db, mode))
    }

    @TestCase
    func aQueryCannotChangeAnInput(): Unit {
        // arrange
        let db = TestDatabase()
        let file = SourceFile(db, "a.cj", "hello")

        // act, assert
        @AssertThrows[IllegalStateException](setsAnInput(db, file))
        @Expect(file.text(db), "hello")
    }

    @TestCase
    func aSnapshotReadsWhatTheDatabaseComputed(): Unit {
        // arrange
        let db = TestDatabase()
        let file = SourceFile(db, "a.cj", "hello")
        length(db, file)
        db.events.take()

        // act
        let result = length(db.snapshot(), file)

        // assert
        @Expect(result, 5)
        @Expect(db.events.take().size, 0)
    }

    @TestCase
    func aWriteWaitsForAQueryInFlightAndCancelsIt(): Unit {
        // arrange
        let db = TestDatabase()
        let file = SourceFile(db, "a.cj", "hello")
        let snapshot = db.snapshot()
        let probe = db.snapshot()
        let reader = spawn {
            try {
                parkedLength(snapshot, file)
                false
            } catch (_: Cancelled) {
                true
            }
        }
        db.parking.parked.remove()

        // act
        let write = spawn {
            file.setText(db).to("bye")
        }
        waitForPendingWrite(probe)
        let blocked = write.tryGet().isNone()
        db.parking.released.add(())
        let cancelled = reader.get()
        let old = write.get()

        // assert
        @Expect(blocked)
        @Expect(cancelled)
        @Expect(old, "hello")
        @Expect(file.text(db), "bye")
    }

    @TestCase
    func aSnapshotUsedAfterAWriteIsCancelled(): Unit {
        // arrange
        let db = TestDatabase()
        let file = SourceFile(db, "a.cj", "hello")
        let snapshot = db.snapshot()
        @Expect(length(snapshot, file), 5)

        // act
        file.setText(db).to("bye")

        // assert
        @AssertThrows[Cancelled](length(snapshot, file))
        @AssertThrows[Cancelled](file.text(snapshot))
        @AssertThrows[Cancelled](SourceFile(snapshot, "b.cj", ""))
        @Expect(length(db.snapshot(), file), 3)
    }

    @TestCase
    func aForgottenSnapshotHoldsUpNoWrite(): Unit {
        // arrange
        let db = TestDatabase()
        let file = SourceFile(db, "a.cj", "hello")
        let forgotten = db.snapshot()
        length(forgotten, file)

        // act
        let old = file.setText(db).to("bye")

        // assert
        @Expect(old, "hello")
        @Expect(file.text(db), "bye")
    }

    @TestCase
    func aSnapshotCannotChangeAnInput(): Unit {
        // arrange
        let db = TestDatabase()
        let file = SourceFile(db, "a.cj", "hello")

        // act, assert
        @AssertThrows[IllegalStateException](file.setText(db.snapshot()).to("bye"))
        @Expect(file.text(db), "hello")
    }

    @TestCase
    func equalFieldsInternToOneValue(): Unit {
        // arrange
        let db = TestDatabase()

        // act
        let a = Name(db, "x")
        let again = Name(db, "x")
        let b = Name(db, "y")

        // assert
        @Expect(a == again)
        @Expect(a != b)
        @Expect(a.text(db), "x")
        @Expect(b.text(db), "y")
        @Expect(b.toString(), "Name(1)")
    }

    @TestCase
    func severalFieldsAreInternedAsOneKey(): Unit {
        // arrange
        let db = TestDatabase()
        let name = Name(db, "HashMap")

        // act
        let a = Qualified(db, "std.collection", name)
        let again = Qualified(db, "std.collection", Name(db, "HashMap"))
        let otherPackage = Qualified(db, "index_map", name)
        let otherName = Qualified(db, "std.collection", Name(db, "HashSet"))

        // assert
        @Expect(a == again)
        @Expect(a != otherPackage)
        @Expect(a != otherName)
        @Expect(a.pkg(db), "std.collection")
        @Expect(a.name(db), name)
    }

    @TestCase
    func aSnapshotInternsIntoTheSameTable(): Unit {
        // arrange
        let db = TestDatabase()
        let name = Name(db, "x")

        // act
        let fromSnapshot = Name(db.snapshot(), "x")

        // assert
        @Expect(fromSnapshot, name)
    }

    @TestCase
    func anInternedValueIsAnArgumentLikeAnyOther(): Unit {
        // arrange
        let db = TestDatabase()

        // act
        let results = [nameLength(db, Name(db, "abc")), nameLength(db, Name(db, "abc")), nameLength(db, Name(db, "de"))]

        // assert
        @Expect(results, [3, 3, 2])
        @Expect(db.events.take(), ["nameLength(Name(0))", "nameLength(Name(1))"])
    }

    @TestCase
    func anInternedResultInternedAgainDoesNotRunWhatReadIt(): Unit {
        // arrange
        let db = TestDatabase()
        let file = SourceFile(db, "a.cj", "foo bar")
        @Expect(firstWordLength(db, file), 3)
        db.events.take()

        // act
        file.setText(db).to("foo baz")
        let result = firstWordLength(db, file)

        // assert
        @Expect(result, 3)
        @Expect(db.events.take(), ["firstWord(SourceFile(0))"])
    }

    /**
     * Spins until the write spawned has cancelled what is in flight, which it does before it waits:
     * `probe` is a snapshot of the revision before it, so it throws from then on.
     */
    private func waitForPendingWrite(probe: TestDatabase): Unit {
        while (true) {
            try {
                probe.unwindIfCancelled()
            } catch (_: Cancelled) {
                return
            }
        }
    }
}
