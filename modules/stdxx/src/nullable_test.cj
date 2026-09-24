package stdxx

import std.unittest.*
import std.unittest.testmacro.*
import stdx.serialization.serialization.*
import stdxx.serialization.*

@Test
@Configure[randomSeed: 42]
class NullableTest {
    @TestCase[value in random()]
    func aValueTravelsAsItself(value: String) {
        // act
        let dm = Nullable.Value(value).serialize()
        let restored = Nullable<String>.deserialize(dm)

        // assert
        @Expect(value, dm.asStringOrThrow())
        @Expect(value, restored.getOrThrow())
    }

    @TestCase
    func nullTravelsAsNull() {
        // act
        let dm = Nullable<String>.Null.serialize()
        let restored = Nullable<String>.deserialize(dm)

        // assert
        @Expect(dm is DataModelNull)
        @Expect(restored.isNull())
    }

    @TestCase
    func askingNullForAValueThrows() {
        // act
        let e = @AssertThrows[NullValueException](Nullable<String>.Null.getOrThrow())

        // assert
        @Expect("value is null", e.message)
    }

    @TestCase
    func anOptionalNullableTellsAnAbsentKeyFromANullOne() {
        // arrange
        let dms = DataModelStruct().add(Field("id", DataModelNull()))

        // act
        let absent = dms.getDeserializedOrNone<Nullable<String>>("missing")
        let explicit = dms.getDeserializedOrNone<Nullable<String>>("id")

        // assert
        @Expect(absent.isNone())
        @Expect(explicit.getOrThrow().isNull())
    }

    @TestCase
    func someNullIsWrittenAsNullRatherThanOmitted() {
        // act
        let dms = DataModelStruct().addFieldIfSome("id", Some(Nullable<String>.Null))

        // assert
        @Expect(dms.getOrThrow("id") is DataModelNull)
    }
}
