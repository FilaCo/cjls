package linked_list

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class ArenaListTest {
    @TestCase
    func pushKeepsValuesInOrder(): Unit {
        // arrange
        let list = ArenaList<String>()

        // act
        list.pushBack("b")
        list.pushBack("c")
        list.pushFront("a")

        // assert
        @Expect(collectArray(list), ["a", "b", "c"])
        @Expect(list.size, 3)
    }

    @TestCase
    func aHandleFindsItsValue(): Unit {
        // arrange
        let list = ArenaList<String>()
        let a = list.pushBack("a")
        let b = list.pushBack("b")

        // act
        list[a] = "A"

        // assert
        @Expect(list[a], "A")
        @Expect(list[b], "b")
        @Expect(list.front, Some(a))
        @Expect(list.back, Some(b))
        @Expect(list.nextOf(a), Some(b))
        @Expect(list.prevOf(a), None<ArenaHandle>)
    }

    @TestCase
    func aMovedElementKeepsItsHandle(): Unit {
        // arrange
        let list = ArenaList<String>()
        let a = list.pushBack("a")
        let b = list.pushBack("b")
        let c = list.pushBack("c")

        // act
        list.moveToBack(a)
        list.moveToFront(c)

        // assert
        @Expect(collectArray(list), ["c", "b", "a"])
        @Expect(collectArray(list.handles()), [c, b, a])
        @Expect(list[a], "a")
    }

    @TestCase
    func removeReturnsTheValueAndInvalidatesTheHandle(): Unit {
        // arrange
        let list = ArenaList<String>()
        let a = list.pushBack("a")
        list.pushBack("b")

        // act
        let removed = list.remove(a)

        // assert
        @Expect(removed, "a")
        @Expect(!list.contains(a))
        @Expect(collectArray(list), ["b"])
        @AssertThrows[NoneValueException](list[a])
        @AssertThrows[NoneValueException](list.moveToBack(a))
    }

    @TestCase
    func aReusedSlotDoesNotAnswerAnOldHandle(): Unit {
        // arrange
        let list = ArenaList<String>()
        let old = list.pushBack("old")
        list.remove(old)

        // act
        let new = list.pushBack("new")

        // assert
        @Expect(new.slot, old.slot)
        @Expect(new != old)
        @Expect(!list.contains(old))
        @Expect(list[new], "new")
    }

    @TestCase
    func popTakesValuesFromEitherEnd(): Unit {
        // arrange
        let list = ArenaList<Int64>()
        for (i in 1..=3) {
            list.pushBack(i)
        }

        // act
        let first = list.popFront()
        let last = list.popBack()

        // assert
        @Expect(first, Some(1))
        @Expect(last, Some(3))
        @Expect(collectArray(list), [2])
    }

    @TestCase
    func clearInvalidatesEveryHandle(): Unit {
        // arrange
        let list = ArenaList<Int64>()
        let handles = Array<ArenaHandle>(4) {i => list.pushBack(i)}

        // act
        list.clear()

        // assert
        @Expect(list.isEmpty())
        @Expect(handles.all {h => !list.contains(h)})
        @Expect(list.popFront(), None<Int64>)
    }

    @TestCase
    func aHandleOfAnotherListIsNotContained(): Unit {
        // arrange
        let one = ArenaList<Int64>()
        let other = ArenaList<Int64>()
        let handle = one.pushBack(1)
        one.remove(handle)
        one.pushBack(2)

        // act, assert
        @Expect(!other.contains(handle))
    }
}
