package index_map.concurrent

import std.collection.*
import std.sync.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class ConcurrentIndexMapTest {
    @TestCase
    func entriesAreIndexedInTheOrderAddedAcrossSegments(): Unit {
        // arrange
        let map = ConcurrentIndexMap<String, Int64>()

        // act
        for (i in 0..1000) {
            map.add("k${i}", i * 10)
        }

        // assert
        @Expect(map.size, 1000)
        for (i in 0..1000) {
            @Expect(map.indexOf("k${i}"), Some(i))
            @Expect(map.get("k${i}"), Some(i * 10))
            @Expect(map.getAt(i).map {entry => entry[0]}, Some("k${i}"))
        }
    }

    @TestCase
    func aKeyAddedAgainKeepsItsPlaceAndItsFirstValue(): Unit {
        // arrange
        let map = ConcurrentIndexMap<String, Int64>()
        map.add("a", 1)
        map.add("b", 2)

        // act
        let (index, there) = map.addWithIndex("a", 3)

        // assert
        @Expect(index, 0)
        @Expect(there, Some(1))
        @Expect(map.get("a"), Some(1))
        @Expect(map.size, 2)
    }

    @TestCase
    func thereIsNoEntryOutsideTheOnesAdded(): Unit {
        // arrange
        let map = ConcurrentIndexMap<String, Int64>()
        map.add("a", 1)

        // act, assert
        @Expect(map.getAt(-1).isNone())
        @Expect(map.getAt(1).isNone())
        @Expect(map.get("b"), None<Int64>)
        @Expect(map.indexOf("b"), None<Int64>)
    }

    @TestCase
    func iterationFollowsTheOrder(): Unit {
        // arrange
        let map = ConcurrentIndexMap<String, Int64>()
        for (key in ["c", "a", "b"]) {
            map.add(key, 0)
        }

        // act
        let keys = map.iterator().map {entry => entry[0]} |> collectArray

        // assert
        @Expect(keys, ["c", "a", "b"])
    }

    @TestCase
    func threadsAddingAtOnceGiveEveryKeyOneIndexAndLeaveNoGap(): Unit {
        // arrange
        let map = ConcurrentIndexMap<Int64, Int64>()
        let start = SyncCounter(1)

        // act: four threads adding the same 2000 keys, each in its own order
        let threads = Array(4) {
            thread => spawn {
                start.waitUntilZero()
                for (i in 0..2000) {
                    let key = if (thread % 2 == 0) { i } else { 1999 - i }
                    map.add(key, key)
                }
            }
        }
        start.dec()
        for (thread in threads) {
            thread.get()
        }

        // assert
        @Expect(map.size, 2000)
        let seen = HashSet<Int64>()
        for (index in 0..2000) {
            let (key, value) = map.getAt(index).getOrThrow()
            @Expect(map.indexOf(key), Some(index))
            @Expect(value, key)
            seen.add(key)
        }
        @Expect(seen.size, 2000)
    }
}

@Test
class ConcurrentIndexSetTest {
    @TestCase
    func anElementAddedAgainKeepsItsPlace(): Unit {
        // arrange
        let set = ConcurrentIndexSet<String>()
        set.add("a")
        set.add("b")

        // act
        let (index, new) = set.addWithIndex("a")

        // assert
        @Expect(index, 0)
        @Expect(new, false)
        @Expect(set.getAt(1), Some("b"))
        @Expect(set.toArray(), ["a", "b"])
    }
}
