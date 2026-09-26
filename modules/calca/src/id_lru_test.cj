package calca

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class IdLruTest {
    @TestCase
    func idsAreInTheOrderTheyWereLastUsed() {
        // arrange
        let lru = IdLru(10)

        // act
        touch(lru, [0, 1, 2, 0])

        // assert
        @Expect([1, 2, 0], indices(lru))
        @Expect(3, lru.size)
        @Expect(lru.contains(Id(0)))
        @Expect(!lru.contains(Id(5)))
        @Expect(!lru.contains(Id(100)))
    }

    @TestCase
    func touchAloneNeverEvicts() {
        // arrange
        let lru = IdLru(1)

        // act
        touch(lru, [0, 1, 2])

        // assert
        @Expect(3, lru.size)
        @Expect([0, 1, 2], indices(lru))
    }

    @TestCase
    func trimEvictsTheOldestDownToTheCapacity() {
        // arrange
        let lru = IdLru(2)
        touch(lru, [0, 1, 2, 0, 3])
        let evicted = ArrayList<Int64>()

        // act
        lru.trim {id => evicted.add(id.index)}

        // assert
        @Expect([1, 2], evicted.toArray())
        @Expect([0, 3], indices(lru))
        @Expect(!lru.contains(Id(1)))
    }

    @TestCase
    func trimUnlinksTheOnlyIdAndTheListStartsAgain() {
        // arrange
        let lru = IdLru(0)
        touch(lru, [4])
        lru.trim {_ => ()}

        // act
        touch(lru, [2, 4])

        // assert
        @Expect([2, 4], indices(lru))
        @Expect(2, lru.size)
    }

    @TestCase
    func touchingAnIdInTheMiddleMovesItToTheEnd() {
        // arrange
        let lru = IdLru(10)
        touch(lru, [0, 1, 2])

        // act
        touch(lru, [1, 1])

        // assert
        @Expect([0, 2, 1], indices(lru))
        @Expect(3, lru.size)
    }

    @TestCase
    func removeUnlinksTheOldestTheNewestOrTheOnlyId() {
        // arrange
        let lru = IdLru(10)
        touch(lru, [0, 1, 2, 3])

        // act
        let oldest = lru.remove(Id(0))
        let newest = lru.remove(Id(3))
        let absent = lru.remove(Id(3))
        let middle = lru.remove(Id(1))
        let only = lru.remove(Id(2))

        // assert
        @Expect([oldest, newest, absent, middle, only], [true, true, false, true, true])
        @Expect(lru.size, 0)
        @Expect(lru.oldestId, None<Id>)
        touch(lru, [5, 1])
        @Expect([5, 1], indices(lru))
        @Expect(lru.oldestId, Id(5))
    }

    @TestCase
    func aNegativeCapacityIsRefused() {
        // act, assert
        @AssertThrows[IllegalArgumentException](IdLru(-1))
    }

    private func touch(lru: IdLru, ids: Array<Int64>): Unit {
        for (index in ids) {
            lru.touch(Id(index))
        }
    }

    private func indices(lru: IdLru): Array<Int64> {
        collectArray(lru).map {id => id.index}
    }
}
