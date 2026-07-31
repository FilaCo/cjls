package stdxx

import std.unittest.*
import std.unittest.testmacro.*
import stdx.serialization.serialization.*

@Test
class NullableTest {
    @TestCase[value in [ "", "hello", "42", "café", "日本語" ]]
    func valueSerializesToUnderlying(value: String) {
        // arrange
        let sut = Nullable.Value(value)

        // act
        let dm = sut.serialize()

        // assert
        @Assert(dm is DataModelString)
        let dms = (dm as DataModelString).getOrThrow()
        @Assert(value, dms.getValue())
    }

    @TestCase
    func nullSerializesToDataModelNull() {
        // arrange
        let sut = Nullable<String>.Null

        // act
        let dm = sut.serialize()

        // assert
        @Assert(dm is DataModelNull)
    }

    @TestCase
    func deserializeNullYieldsNull() {
        // arrange
        let dm = DataModelNull()

        // act
        let restored = Nullable<String>.deserialize(dm)

        // assert
        @Assert(restored.isNull())
    }

    @TestCase[value in [ "", "hello", "42", "日本語" ]]
    func deserializeNonNullYieldsValue(value: String) {
        // arrange
        let dm = DataModelString(value)

        // act
        let restored = Nullable<String>.deserialize(dm)

        // assert
        @Assert(restored.isValue())
        @Assert(value, restored.getOrThrow())
    }

    @TestCase[value in [ "", "hello", "42", "日本語" ]]
    func valueRoundTrip(value: String) {
        // arrange
        let original = Nullable<String>.Value(value)

        // act
        let restored = Nullable<String>.deserialize(original.serialize())

        // assert
        @Assert(restored.isValue())
        @Assert(value, restored.getOrThrow())
    }

    @TestCase
    func nullRoundTrip() {
        // arrange
        let original = Nullable<String>.Null

        // act
        let restored = Nullable<String>.deserialize(original.serialize())

        // assert
        @Assert(restored.isNull())
    }

    @TestCase
    func getOnNullThrows() {
        // arrange
        let sut = Nullable<String>.Null

        // act
        let e = @AssertThrows[NullValueException](sut.getOrThrow())

        // assert
        @Expect("value is null", e.message)
    }
}
