package lru_set

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class LruSetTest {
    @TestCase
    func elementsAreInTheOrderTheyWereLastUsed() {
        // arrange
        let set = LruSet<String>(10)

        // act
        for (value in ["a", "b", "c", "a"]) {
            set.touch(value)
        }

        // assert
        @Expect(["b", "c", "a"], collectArray(set))
        @Expect(3, set.size)
        @Expect(set.contains("a"))
        @Expect(!set.contains("z"))
    }

    @TestCase
    func touchAloneNeverEvicts() {
        // arrange
        let set = LruSet<String>(1)

        // act
        for (value in ["a", "b", "c"]) {
            set.touch(value)
        }

        // assert
        @Expect(3, set.size)
        @Expect(["a", "b", "c"], collectArray(set))
    }

    @TestCase
    func trimEvictsTheOldestDownToTheCapacity() {
        // arrange
        let set = LruSet<String>(2)
        for (value in ["a", "b", "c", "a", "d"]) {
            set.touch(value)
        }
        let evicted = ArrayList<String>()

        // act
        set.trim {value => evicted.add(value)}

        // assert
        @Expect(["b", "c"], evicted.toArray())
        @Expect(["a", "d"], collectArray(set))
    }

    @TestCase
    func aSmallerCapacityEvictsNothingUntilTheNextTrim() {
        // arrange
        let set = LruSet<String>(3)
        for (value in ["a", "b", "c"]) {
            set.touch(value)
        }

        // act
        set.capacity = 1

        // assert
        @Expect(3, set.size)
        set.trim {_ => ()}
        @Expect(["c"], collectArray(set))
    }

    @TestCase
    func removeUnlinksTheOldestTheNewestAndTheOnly() {
        // arrange
        let set = LruSet<String>(10)
        for (value in ["a", "b", "c"]) {
            set.touch(value)
        }

        // act, assert
        @Expect(set.remove("a"))
        @Expect(["b", "c"], collectArray(set))
        @Expect(set.remove("c"))
        @Expect(["b"], collectArray(set))
        @Expect(set.remove("b"))
        @Expect(set.isEmpty())
        @Expect(Array<String>(), collectArray(set))
        @Expect(!set.remove("b"))
    }

    @TestCase
    func aFreedSlotIsReusedRatherThanGrown() {
        // arrange
        let set = LruSet<String>(1)
        for (value in ["a", "b", "c"]) {
            set.touch(value)
        }
        set.remove("b")
        set.trim {_ => ()}

        // act
        set.touch("d")
        set.touch("e")

        // assert
        @Expect(3, set.slotCount)
        @Expect(["c", "d", "e"], collectArray(set))
    }

    @TestCase
    func aNegativeCapacityIsRefused() {
        // act, assert
        @AssertThrows[IllegalArgumentException](LruSet<String>(-1))
        @AssertThrows[IllegalArgumentException](LruSet<String>(1).capacity = -1)
    }
}
