package stdxx

import std.collection.HashMap
import std.unittest.*
import std.unittest.testmacro.*
import stdx.serialization.serialization.*

@Test
class IntegerOrStringTest {
    @TestCase[value in [ 0, 42, - 1, - 999, 2147483647 ]]
    func integerRoundTrip(value: Int32) {
        // arrange
        let original = Integer(value)

        // act
        let restored = IntegerOrString.deserialize(original.serialize())

        // assert
        @Assert(restored, Integer(value))
    }

    @TestCase[value in [ "", "hello", "42", "with space", "café", "日本語" ]]
    func stringRoundTrip(value: String) {
        // arrange
        let original = IntegerOrString.String(value)

        // act
        let restored = IntegerOrString.deserialize(original.serialize())

        // assert
        @Assert(restored, IntegerOrString.String(value))
    }

    @TestCase
    func deserializeRejectsBool() {
        // arrange
        let dm = DataModelBool(true)

        // act & assert
        @AssertThrows[DataModelException](IntegerOrString.deserialize(dm))
    }

    @TestCase
    func toStringRendersRawScalar() {
        // arrange
        let asInt = IntegerOrString.Integer(42)
        let asStr = IntegerOrString.String("hello")

        // act & assert
        @Assert("42", asInt.toString())
        @Assert("hello", asStr.toString())
    }

    @TestCase
    func getIntegerOnStringThrows() {
        // arrange
        let sut = IntegerOrString.String("hello")

        // act
        let e = @AssertThrows[UnexpectedVariantException](sut.getIntegerOrThrow())

        // assert
        @Expect("expected `Integer` variant, got `String`", e.message)
    }

    @TestCase
    func getStringOnIntegerThrows() {
        // arrange
        let sut = IntegerOrString.Integer(42)

        // act
        let e = @AssertThrows[UnexpectedVariantException](sut.getStringOrThrow())

        // assert
        @Expect("expected `String` variant, got `Integer`", e.message)
    }
}

@Test
class IntegerOrStringHashTest {
    // JSON-RPC request ids are hash map keys - a peer's id is built here, the
    // matching one is rebuilt from the wire, and the two have to land in the same
    // bucket or a response never finds what it is answering.

    @TestCase
    func integerAndStringKeysDoNotCollapse() {
        // arrange - `42` and `"42"` are different request ids, and `toString` maps
        // them onto the same text, so hashing must not go through it
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
