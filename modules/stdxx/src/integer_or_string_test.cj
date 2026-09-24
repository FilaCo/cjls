package stdxx

import std.collection.HashMap
import std.unittest.*
import std.unittest.testmacro.*
import stdx.serialization.serialization.*

@Test
@Configure[randomSeed: 42]
class IntegerOrStringTest {
    @TestCase[value in random()]
    func anIntegerRoundTrips(value: Int32) {
        // act
        let restored = IntegerOrString.deserialize(Integer(value).serialize())

        // assert
        @Expect(Integer(value), restored)
    }

    @TestCase[value in random()]
    func aStringRoundTrips(value: String) {
        // act
        let restored = IntegerOrString.deserialize(IntegerOrString.String(value).serialize())

        // assert
        @Expect(IntegerOrString.String(value), restored)
    }

    @TestCase[dm in [DataModelBool(true), DataModelNull(), DataModelInt(Int64(Int32.Max) + 1)]]
    func anythingElseIsRefused(dm: DataModel) {
        // act & assert
        @AssertThrows[DataModelException](IntegerOrString.deserialize(dm))
    }

    @TestCase
    func toStringRendersTheBareValue() {
        // act & assert
        @Expect("42", Integer(42).toString())
        @Expect("hello", IntegerOrString.String("hello").toString())
    }

    @TestCase
    func askingForTheOtherVariantThrows() {
        // act
        let onString = @AssertThrows[UnexpectedVariantException](IntegerOrString.String("1").getIntegerOrThrow())
        let onInteger = @AssertThrows[UnexpectedVariantException](Integer(1).getStringOrThrow())

        // assert
        @Expect("expected `Integer` variant, got `String`", onString.message)
        @Expect("expected `String` variant, got `Integer`", onInteger.message)
    }

    @TestCase
    func anIntegerAndItsTextAreDifferentKeys() {
        // arrange - `toString` maps `42` and `"42"` onto the same text, so hashing must not go through it
        let map = HashMap<IntegerOrString, String>()

        // act
        map[Integer(42)] = "integer"
        map[IntegerOrString.String("42")] = "string"

        // assert
        @Expect(2, map.size)
        @Expect("integer", map[Integer(42)])
        @Expect("string", map[IntegerOrString.String("42")])
    }
}
