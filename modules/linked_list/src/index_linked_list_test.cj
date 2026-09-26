package linked_list

import std.collection.*
import std.random.*
import std.unittest.*
import std.unittest.testmacro.*

func indices(list: IndexLinkedList): Array<Int64> {
    collectArray(list)
}

func reversed(list: IndexLinkedList): Array<Int64> {
    let out = ArrayList<Int64>()
    var current = list.back
    while (let Some(index) <- current) {
        out.add(index)
        current = list.prevOf(index)
    }
    out.toArray()
}

@Test
class IndexLinkedListTest {
    @TestCase
    func anEmptyListHasNoEnds(): Unit {
        // arrange
        let list = IndexLinkedList()

        // act, assert
        @Expect(list.isEmpty())
        @Expect(list.front, None<Int64>)
        @Expect(list.back, None<Int64>)
        @Expect(list.popFront(), None<Int64>)
        @Expect(list.popBack(), None<Int64>)
        @Expect(indices(list), Array<Int64>())
    }

    @TestCase
    func moveToBackAddsInOrder(): Unit {
        // arrange
        let list = IndexLinkedList()

        // act
        list.moveToBack(3)
        list.moveToBack(0)
        list.moveToBack(7)

        // assert
        @Expect(indices(list), [3, 0, 7])
        @Expect(list.size, 3)
        @Expect(list.front, Some(3))
        @Expect(list.back, Some(7))
    }

    @TestCase
    func moveToFrontAddsInReverseOrder(): Unit {
        // arrange
        let list = IndexLinkedList()

        // act
        list.moveToFront(3)
        list.moveToFront(0)
        list.moveToFront(7)

        // assert
        @Expect(indices(list), [7, 0, 3])
    }

    @TestCase
    func movingAnIndexInTheListDoesNotAddItAgain(): Unit {
        // arrange
        let list = IndexLinkedList()
        for (i in [1, 2, 3, 4]) {
            list.moveToBack(i)
        }

        // act
        list.moveToBack(2)
        list.moveToFront(4)
        list.moveToBack(3)

        // assert
        @Expect(indices(list), [4, 1, 2, 3])
        @Expect(reversed(list), [3, 2, 1, 4])
        @Expect(list.size, 4)
    }

    @TestCase
    func movingTheOnlyIndexKeepsIt(): Unit {
        // arrange
        let list = IndexLinkedList()
        list.moveToBack(5)

        // act
        list.moveToFront(5)
        list.moveToBack(5)

        // assert
        @Expect(indices(list), [5])
        @Expect(list.front, Some(5))
        @Expect(list.back, Some(5))
    }

    @TestCase
    func removeTakesAnIndexFromTheMiddleOrAnEnd(): Unit {
        // arrange
        let list = IndexLinkedList()
        for (i in [1, 2, 3, 4]) {
            list.moveToBack(i)
        }

        // act
        let middle = list.remove(2)
        let front = list.remove(1)
        let back = list.remove(4)
        let absent = list.remove(2)

        // assert
        @Expect(middle && front && back)
        @Expect(!absent)
        @Expect(indices(list), [3])
        @Expect(!list.contains(2))
        @Expect(list.contains(3))
    }

    @TestCase
    func popTakesFromEitherEnd(): Unit {
        // arrange
        let list = IndexLinkedList()
        for (i in [1, 2, 3]) {
            list.moveToBack(i)
        }

        // act
        let first = list.popFront()
        let last = list.popBack()

        // assert
        @Expect(first, Some(1))
        @Expect(last, Some(3))
        @Expect(indices(list), [2])
    }

    @TestCase
    func aListEmptiedFillsAgain(): Unit {
        // arrange
        let list = IndexLinkedList()
        for (i in 0..10) {
            list.moveToBack(i)
        }
        list.clear()

        // act
        list.moveToBack(4)
        list.moveToFront(9)

        // assert
        @Expect(list.size, 2)
        @Expect(indices(list), [9, 4])
        @Expect(!list.contains(0))
    }

    @TestCase
    func aNegativeIndexIsRefused(): Unit {
        // arrange
        let list = IndexLinkedList()

        // act, assert
        @AssertThrows[IllegalArgumentException](list.moveToBack(-1))
        @Expect(!list.contains(-1))
        @Expect(!list.remove(-1))
    }

    @TestCase
    func neighboursOfAnIndexNotInTheListAreAnError(): Unit {
        // arrange
        let list = IndexLinkedList()
        list.moveToBack(1)

        // act, assert
        @AssertThrows[NoneValueException](list.nextOf(0))
        @AssertThrows[NoneValueException](list.prevOf(2))
        @Expect(list.nextOf(1), None<Int64>)
    }
}

@Test
@Configure[randomSeed: 17]
class IndexLinkedListPropertyTest {
    /**
     * Random moves and removals against an `ArrayList` holding the same order.
     */
    @TestCase
    func itKeepsTheOrderAnArrayWould(): Unit {
        // arrange
        let random = Random(17)
        let list = IndexLinkedList()
        let model = ArrayList<Int64>()

        for (_ in 0..2000) {
            // act
            let index = random.nextInt64(32)
            match (random.nextInt64(5)) {
                case 0 | 1 =>
                    list.moveToBack(index)
                    model.removeIf {i => i == index}
                    model.add(index)
                case 2 =>
                    list.moveToFront(index)
                    model.removeIf {i => i == index}
                    model.add(index, at: 0)
                case 3 =>
                    let removed = list.remove(index)
                    @Assert(removed, model.contains(index))
                    model.removeIf {i => i == index}
                case _ =>
                    let popped = list.popFront()
                    let expected = if (model.isEmpty()) {
                        None<Int64>
                    } else {
                        let first = model[0]
                        model.remove(at: 0)
                        Some(first)
                    }
                    @Assert(popped, expected)
            }

            // assert
            @Assert(indices(list), model.toArray())
            @Assert(list.size, model.size)
        }
        let back = model.toArray()
        back.reverse()
        @Expect(reversed(list), back)
    }
}
