package index_map

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class IndexSetTest {
    @TestCase
    func elementsKeepTheOrderTheyWereAddedIn() {
        // act
        let set = IndexSet<String>(["c", "a", "b", "a"])

        // assert
        @Expect(["c", "a", "b"], set.toArray())
        @Expect("[c, a, b]", set.toString())
        @Expect(3, set.size)
    }

    @TestCase
    func addingAnElementAgainKeepsItsPlace() {
        // arrange
        let set = IndexSet<String>(["a", "b"])

        // act
        let (added, isNew) = set.addWithIndex("c")
        let (existing, isAgain) = set.addWithIndex("a")

        // assert
        @Expect(2, added)
        @Expect(isNew)
        @Expect(0, existing)
        @Expect(!isAgain)
        @Expect(!set.add("b"))
        @Expect(["a", "b", "c"], set.toArray())
    }

    @TestCase
    func anElementIsFoundByItsIndexAndItsIndexByIt() {
        // arrange
        let set = IndexSet<String>(["a", "b"])

        // act, assert
        @Expect(Some(1), set.indexOf("b"))
        @Expect(None<Int64>, set.indexOf("z"))
        @Expect(Some("a"), set.getAt(0))
        @Expect(None<String>, set.getAt(2))
    }

    @TestCase
    func shiftRemoveKeepsTheOrderOfTheRest() {
        // arrange
        let set = IndexSet<String>(["a", "b", "c", "d"])

        // act
        let removed = set.shiftRemove("b")

        // assert
        @Expect(removed)
        @Expect(!set.remove("b"))
        @Expect(["a", "c", "d"], set.toArray())
        @Expect(Some(1), set.indexOf("c"))
    }

    @TestCase
    func swapRemoveMovesTheLastIntoTheGap() {
        // arrange
        let set = IndexSet<String>(["a", "b", "c", "d"])

        // act
        let removed = set.swapRemove("b")

        // assert
        @Expect(removed)
        @Expect(["a", "d", "c"], set.toArray())
        @Expect(Some(1), set.indexOf("d"))
    }

    @TestCase
    func retainAndRemoveIfKeepTheOrderOfTheRest() {
        // arrange
        let set = IndexSet<Int64>([5, 1, 4, 2, 3])

        // act
        set.removeIf {n => n % 2 == 0}
        set.retain(all: HashSet<Int64>([3, 5, 7]))

        // assert
        @Expect([5, 3], set.toArray())
    }

    @TestCase
    func aSubsetIsOneWhateverTheOrder() {
        // arrange
        let set = IndexSet<Int64>([3, 1])

        // act, assert
        @Expect(set.subsetOf(HashSet<Int64>([1, 2, 3])))
        @Expect(!set.subsetOf(IndexSet<Int64>([1, 2])))
    }

    @TestCase
    func aCloneIsIndependent() {
        // arrange
        let set = IndexSet<String>(["a"])

        // act
        let copy = set.clone()
        copy.add("b")

        // assert
        @Expect(["a"], set.toArray())
        @Expect(["a", "b"], copy.toArray())
    }
}
