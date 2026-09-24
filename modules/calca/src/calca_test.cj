package calca

import std.collection.*
import std.sync.*
import std.unittest.*
import std.unittest.testmacro.*
import calca.macros.*

interface TestDb <: Database {
    func log(event: String): Unit
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

class TestDatabase <: TestDb & Resource {
    private TestDatabase(private let storage_: Storage, let events: Events) {}

    init() {
        this(Storage(), Events())
    }

    public prop storage: Storage {
        get() {
            storage_
        }
    }

    public func log(event: String): Unit {
        events.add(event)
    }

    func snapshot(): TestDatabase {
        TestDatabase(storage_.snapshot(), events)
    }

    public func isClosed(): Bool {
        storage_.isClosed()
    }

    public func close(): Unit {
        storage_.close()
    }
}

@Input
struct SourceFile {
    let path: String
    var text: String
}

@Input
struct Mode {
    var cyclic: Bool
}

@Tracked
func length(db: TestDb, file: SourceFile): Int64 {
    db.log("length(${file})")
    file.text(db).size
}

@Tracked
func isLong(db: TestDb, file: SourceFile): Bool {
    db.log("isLong(${file})")
    length(db, file) > 5
}

@Tracked
func pathLength(db: TestDb, file: SourceFile): Int64 {
    db.log("pathLength(${file})")
    file.path(db).size
}

@Tracked
func answer(db: TestDb): Int64 {
    db.log("answer")
    42
}

@Tracked[noEq]
func lengthNoEq(db: TestDb, file: SourceFile): Int64 {
    db.log("lengthNoEq(${file})")
    file.text(db).size
}

@Tracked
func afterNoEq(db: TestDb, file: SourceFile): Int64 {
    db.log("afterNoEq(${file})")
    lengthNoEq(db, file)
}

@Tracked
func first(db: TestDb, mode: Mode): Int64 {
    second(db, mode) + 1
}

@Tracked
func second(db: TestDb, mode: Mode): Int64 {
    if (mode.cyclic(db)) {
        first(db, mode)
    } else {
        0
    }
}

@Tracked
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
        var result = 0
        try (snapshot = db.snapshot()) {
            result = length(snapshot, file)
        }

        // assert
        @Expect(result, 5)
        @Expect(db.events.take().size, 0)
    }

    @TestCase
    func aWriteCancelsASnapshotAndWaitsForItToClose(): Unit {
        // arrange
        let db = TestDatabase()
        let file = SourceFile(db, "a.cj", "hello")
        let snapshot = db.snapshot()

        // act
        let write = spawn {
            file.setText(db).to("bye")
        }
        let cancelled = waitForCancellation(snapshot)
        let blocked = !write.tryGet().isSome()
        snapshot.close()
        let old = write.get()

        // assert
        @Expect(cancelled)
        @Expect(blocked)
        @Expect(old, "hello")
        @Expect(file.text(db), "bye")
    }

    @TestCase
    func aQueryOnASnapshotBeingCancelledThrows(): Unit {
        // arrange
        let db = TestDatabase()
        let file = SourceFile(db, "a.cj", "hello")
        let snapshot = db.snapshot()
        let write = spawn {
            file.setText(db).to("bye")
        }
        waitForCancellation(snapshot)

        // act
        let thrown = try {
            length(snapshot, file)
            false
        } catch (_: Cancelled) {
            true
        }

        // assert
        @Expect(thrown)
        snapshot.close()
        write.get()
        @Expect(length(db, file), 3)
    }

    /**
     * Spins until the write spawned has asked every other handle to close, which it does before it
     * waits for them.
     */
    private func waitForCancellation(db: TestDatabase): Bool {
        while (true) {
            try {
                db.unwindIfCancelled()
            } catch (_: Cancelled) {
                return true
            }
        }
        false
    }
}
