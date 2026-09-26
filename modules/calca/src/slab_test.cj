package calca

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class SlabTest {
    @TestCase
    func aRemovedValueIsGoneAndItsSlotReusedWithTheNextGeneration() {
        // arrange
        let slab = Slab<String>()
        let foo = slab.insert("foo")
        slab.insert("bar")

        // act
        let removed = slab.remove(foo)
        let quux = slab.insert("quux")

        // assert
        @Expect(removed, "foo")
        @Expect(quux.index, foo.index)
        @Expect(quux.generation, foo.generation + 1)
        @Expect(slab.get(foo), None<String>)
        @Expect(slab.get(quux), "quux")
        @Expect(slab.remove(foo), None<String>)
        @Expect(slab.size, 2)
        @Expect(slab.slotCount, 2)
    }

    @TestCase
    func theSlotVacatedLastIsTakenFirst() {
        // arrange
        let slab = Slab<Int64>()
        let ids = Array<Id>(6, {i => slab.insert(i)})
        slab.remove(ids[3])
        slab.remove(ids[5])

        // act
        let first = slab.insert(10)
        let second = slab.insert(11)
        let third = slab.insert(12)

        // assert
        @Expect([first.index, second.index, third.index], [5, 3, 6])
    }

    @TestCase
    func aSlotAtTheMaximumGenerationIsRetired() {
        // arrange
        let slab = Slab<String>()
        slab.maxGeneration = 1
        let a = slab.insert("a")
        slab.remove(a)
        let b = slab.insert("b")

        // act
        slab.remove(b)
        let c = slab.insert("c")

        // assert
        @Expect(b.index, a.index)
        @Expect(b.generation, 1u32)
        @Expect(c.index, 1)
        @Expect(c.generation, 0u32)
        @Expect(slab.get(b), None<String>)
        @Expect(slab.getAt(a.index).isNone())
    }

    @TestCase
    func anIdPrintsItsGenerationOnceItHasOne() {
        // act, assert
        @Expect(Id(3).toString(), "3")
        @Expect(Id(3, generation: 1).toString(), "3g1")
        @Expect(Id(3, generation: UInt32.Max).index, 3)
        @Expect(Id(3, generation: UInt32.Max).generation, UInt32.Max)
        @Expect(Id(3) != Id(3, generation: 1))
        @AssertThrows[IllegalArgumentException](Id(1 << 32))
    }
}
