package stdxx

// Exactly the imports a user of `@DeriveExt[Serializable]` needs - nothing from `std.collection`:
// the tuple variants below once wrote themselves through an `ArrayList`.
import std.unittest.*
import std.unittest.testmacro.*
import stdx.serialization.serialization.*
import stdxx.serialization.*
import stdxx.deriving.*

@DeriveExt[Serializable]
enum DerivedLabel {
    | Text(String)
    | Offsets(UInt32, UInt32)
    | Signed(Int64, Int64)
}

@Test
class DeriveTupleVariantTest {
    @TestCase
    func aVariantWithSeveralPayloadsIsReadFromAnArrayOfThatLength() {
        // arrange
        let pair = DerivedLabel.Offsets(3, 7).serialize()

        // act
        let restored = DerivedLabel.deserialize(pair)

        // assert
        @Expect(2, pair.asSeqOrThrow().getItems().size)
        @Expect(match (restored) {
            case Offsets(start, end) => start == 3 && end == 7
            case _ => false
        })
    }

    @TestCase
    func aTupleWithAnUnreadableItemGivesWayToTheNextOne() {
        // act - `-1` is no `UInt32`
        let restored = DerivedLabel.deserialize(DerivedLabel.Signed(-1, 2).serialize())

        // assert
        @Expect(match (restored) {
            case Signed(start, end) => start == -1 && end == 2
            case _ => false
        })
    }

    @TestCase
    func anArrayOfAnotherLengthMatchesNoTupleVariant() {
        // arrange
        let triple = DataModelSeq()
        triple.add(DataModelInt(1))
        triple.add(DataModelInt(2))
        triple.add(DataModelInt(3))

        // act & assert
        @AssertThrows[DataModelException](DerivedLabel.deserialize(triple))
    }
}
