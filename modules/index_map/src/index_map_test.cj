package index_map

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

private func mapOf(keys: Array<String>): IndexMap<String, Int64> {
    let map = IndexMap<String, Int64>()
    for (i in 0..keys.size) {
        map.add(keys[i], i)
    }
    map
}

private func keysOf<V>(map: IndexMap<String, V>): Array<String> {
    map.keys().toArray()
}

@Test
class IndexMapTest {
    @TestCase
    func entriesKeepTheOrderTheyWereAddedIn() {
        // act
        let map = mapOf(["c", "a", "b"])

        // assert
        @Expect(["c", "a", "b"], keysOf(map))
        @Expect([0, 1, 2], map.values().toArray())
        @Expect("[(c, 0), (a, 1), (b, 2)]", map.toString())
    }

    @TestCase
    func replacingAValueKeepsItsPlace() {
        // arrange
        let map = mapOf(["a", "b", "c"])

        // act
        let replaced = map.add("a", 10)

        // assert
        @Expect(Some(0), replaced)
        @Expect("[(a, 10), (b, 1), (c, 2)]", map.toString())
    }

    @TestCase
    func addWithIndexGivesTheEntrysPosition() {
        // arrange
        let map = mapOf(["a", "b"])

        // act
        let (added, nothing) = map.addWithIndex("c", 2)
        let (existing, replaced) = map.addWithIndex("a", 10)

        // assert
        @Expect(2, added)
        @Expect(None<Int64>, nothing)
        @Expect(0, existing)
        @Expect(Some(0), replaced)
    }

    @TestCase
    func anEntryIsFoundByKeyAndByIndex() {
        // arrange
        let map = mapOf(["a", "b"])

        // act & assert
        @Expect(Some(1), map.indexOf("b"))
        @Expect(None<Int64>, map.indexOf("z"))
        @Expect(Some(1), map.get("b"))
        @Expect(1, map["b"])
        @Expect(Some("b"), map.getAt(1).map {entry => entry[0]})
        @Expect(map.getAt(2).isNone())
        @Expect(map.getAt(-1).isNone())
    }

    @TestCase
    func aMissingKeyThrowsFromTheSubscript() {
        // arrange
        let map = mapOf(["a"])

        // act & assert
        @AssertThrows[NoneValueException](map["z"])
    }

    @TestCase
    func shiftRemoveKeepsTheOrderOfTheRest() {
        // arrange
        let map = mapOf(["a", "b", "c", "d"])

        // act
        let removed = map.shiftRemove("b")

        // assert
        @Expect(Some(1), removed)
        @Expect(["a", "c", "d"], keysOf(map))
        @Expect(Some(1), map.indexOf("c"))
        @Expect(Some(2), map.indexOf("d"))
    }

    @TestCase
    func swapRemoveMovesTheLastEntryIntoTheGap() {
        // arrange
        let map = mapOf(["a", "b", "c", "d"])

        // act
        let removed = map.swapRemove("b")

        // assert
        @Expect(Some(1), removed)
        @Expect(["a", "d", "c"], keysOf(map))
        @Expect(Some(1), map.indexOf("d"))
    }

    @TestCase
    func swapRemovingTheLastEntryMovesNothing() {
        // arrange
        let map = mapOf(["a", "b"])

        // act
        map.swapRemove("b")

        // assert
        @Expect(["a"], keysOf(map))
        @Expect(Some(0), map.indexOf("a"))
    }

    @TestCase
    func removingAMissingKeyChangesNothing() {
        // arrange
        let map = mapOf(["a", "b"])

        // act & assert
        @Expect(None<Int64>, map.remove("z"))
        @Expect(None<Int64>, map.swapRemove("z"))
        @Expect(["a", "b"], keysOf(map))
    }

    @TestCase
    func removeIfKeepsTheOrderOfTheRest() {
        // arrange
        let map = mapOf(["a", "b", "c", "d", "e"])

        // act
        map.removeIf {_, value => value % 2 == 1}

        // assert
        @Expect(["a", "c", "e"], keysOf(map))
        @Expect(Some(2), map.indexOf("e"))
    }

    @TestCase
    func aThrowingPredicateLeavesTheMapAsItWas() {
        // arrange
        let map = mapOf(["a", "b", "c"])

        // act
        @AssertThrows[IllegalStateException](map.removeIf {key, _ =>
            if (key == "c") {
                throw IllegalStateException()
            }
            true
        })

        // assert
        @Expect(["a", "b", "c"], keysOf(map))
    }

    @TestCase
    func removeAllKeepsTheOrderOfTheRest() {
        // arrange
        let map = mapOf(["a", "b", "c", "d"])

        // act
        map.remove(all: ["d", "b", "z"])

        // assert
        @Expect(["a", "c"], keysOf(map))
        @Expect(Some(1), map.indexOf("c"))
    }

    @TestCase
    func theEntryViewAddsReplacesAndRemoves() {
        // arrange
        let map = mapOf(["a", "b", "c"])

        // act
        map.entryView("z").value = 9
        map.entryView("a").value = 10
        map.entryView("b").value = None

        // assert
        @Expect("[(a, 10), (c, 2), (z, 9)]", map.toString())
        @Expect("c", map.entryView("c").key)
        @Expect(Some(2), map.entryView("c").value)
    }

    @TestCase
    func theKeysAndValuesSeeLaterChanges() {
        // arrange
        let map = mapOf(["a"])
        let keys = map.keys()
        let values = map.values()

        // act
        map.add("b", 1)

        // assert
        @Expect(["a", "b"], keys.toArray())
        @Expect([0, 1], values.toArray())
        @Expect(keys.contains("b"))
        @Expect(keys.contains(all: ["a", "b"]))
        @Expect(!keys.contains(all: ["a", "z"]))
    }

    @TestCase
    func aCloneIsIndependent() {
        // arrange
        let map = mapOf(["a", "b"])

        // act
        let copy = map.clone()
        copy.add("c", 2)
        copy.remove("a")

        // assert
        @Expect(["a", "b"], keysOf(map))
        @Expect(["b", "c"], keysOf(copy))
    }

    @TestCase
    func aRepeatedKeyInTheElementsKeepsItsFirstPlace() {
        // act
        let map = IndexMap<String, Int64>([("a", 0), ("b", 1), ("a", 2)])

        // assert
        @Expect("[(a, 2), (b, 1)]", map.toString())
    }

    @TestCase
    func clearEmptiesTheMap() {
        // arrange
        let map = mapOf(["a", "b"])

        // act
        map.clear()

        // assert
        @Expect(map.isEmpty())
        @Expect(map.indexOf("a").isNone())
    }
}

private func positionIn(model: ArrayList<(Int64, Int64)>, key: Int64): ?Int64 {
    for (i in 0..model.size where model[i][0] == key) {
        return i
    }
    None
}

@Test
@Configure[randomSeed: 42]
class IndexMapModelTest {
    /**
     * Replays random operations on the map and on a plain list searched linearly, which is obviously
     * right, and checks after each that they hold the same entries in the same order.
     */
    @TestCase[operations in random()]
    func behavesAsAnOrderedListOfEntries(operations: Array<Int64>) {
        // arrange
        let map = IndexMap<Int64, Int64>()
        let model = ArrayList<(Int64, Int64)>()

        for (step in 0..operations.size) {
            // act - a small key range, so keys collide; `%` keeps the sign, hence the `+ 32`
            let code = operations[step] % 32 + 32
            let key = code / 4 % 8
            let position = positionIn(model, key)
            // what the model had under the key: what `add` replaces and a removal returns
            let expected = position.map {i => model[i][1]}
            let actual = match (code % 4) {
                case 0 | 1 =>
                    match (position) {
                        case Some(i) => model[i] = (key, step)
                        case None => model.add((key, step))
                    }
                    map.add(key, step)
                case 2 =>
                    if (let Some(i) <- position) {
                        model.remove(at: i)
                    }
                    map.shiftRemove(key)
                case _ =>
                    if (let Some(i) <- position) {
                        let last = model[model.size - 1]
                        model.remove(at: model.size - 1)
                        if (i < model.size) {
                            model[i] = last
                        }
                    }
                    map.swapRemove(key)
            }

            // assert
            @Assert(expected, actual)
            @Assert(model.map {entry => entry[0]}.toArray(), map.keys().toArray())
            @Assert(model.map {entry => entry[1]}.toArray(), map.values().toArray())
            for (i in 0..model.size) {
                @Assert(Some(i), map.indexOf(model[i][0]))
            }
        }
    }
}
