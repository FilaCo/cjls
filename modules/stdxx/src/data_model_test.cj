package stdxx

import std.unittest.*
import std.unittest.testmacro.*
import stdx.encoding.json.*
import stdx.serialization.serialization.*

@Test
class DataModelShapeTest {
    @TestCase
    func matchingShapesAreUnwrapped() {
        // act & assert
        @Expect(1, DataModelStruct().add(field("k", 1)).asStructOrThrow().getDeserializedOrThrow<Int64>("k"))
        @Expect("hello", DataModelString("hello").asStringOrThrow())
        @Expect(42, DataModelInt(42).asIntOrThrow())
    }

    @TestCase
    func mismatchedShapesThrowNamingWhatWasWanted() {
        // act
        let onStruct = @AssertThrows[DataModelException](DataModelInt(1).asStructOrThrow())
        let onString = @AssertThrows[DataModelException](DataModelInt(1).asStringOrThrow())
        let onInt = @AssertThrows[DataModelException](DataModelString("1").asIntOrThrow())

        // assert
        @Expect("expected `DataModelStruct`", onStruct.message)
        @Expect("expected `DataModelString`", onString.message)
        @Expect("expected `DataModelInt`", onInt.message)
    }
}

@Test
class GetOrNoneTest {
    @TestCase
    func absentKeyReturnsNone() {
        // arrange
        let dms = DataModelStruct().add(field("present", 1))

        // act & assert
        @Assert(dms.getOrNone("missing").isNone())
    }

    @TestCase
    func presentKeyReturnsSome() {
        // arrange
        let dms = DataModelStruct().add(field("value", 42))

        // act
        let result = dms.getOrNone("value")

        // assert
        @Assert(result.isSome())
        @Expect(42, result.getOrThrow().asIntOrThrow())
    }

    @TestCase
    func presentNullIsDistinctFromAbsent() {
        // arrange
        let dms = DataModelStruct().add(Field("nullable", DataModelNull()))

        // act
        let result = dms.getOrNone("nullable")

        // assert
        @Assert(result.isSome())
        @Assert(result.getOrThrow() is DataModelNull)
    }

    @TestCase
    func lastWinsForDuplicateKeys() {
        // arrange
        let dms = DataModelStruct().add(field("k", 1)).add(field("k", 2))

        // act
        let result = dms.getOrNone("k")

        // assert
        @Assert(result.isSome())
        @Expect(2, result.getOrThrow().asIntOrThrow())
    }
}

@Test
class GetOrThrowTest {
    @TestCase
    func presentKeyReturnsItsData() {
        // arrange
        let dms = DataModelStruct().add(field("value", "hello"))

        // act
        let result = dms.getOrThrow("value")

        // assert
        @Assert(result is DataModelString)
        @Expect("hello", (result as DataModelString).getOrThrow().getValue())
    }

    @TestCase
    func absentKeyThrows() {
        // arrange
        let dms = DataModelStruct().add(field("present", 1))

        // act
        let e = @AssertThrows[DataModelException](dms.getOrThrow("missing"))

        // assert
        @Expect("required field \"missing\" is absent", e.message)
    }

    @TestCase
    func presentNullDoesNotThrow() {
        // arrange - an explicit null is a present field
        let dms = DataModelStruct().add(Field("nullable", DataModelNull()))

        // act
        let result = dms.getOrThrow("nullable")

        // assert
        @Assert(result is DataModelNull)
    }
}

@Test
class GetDeserializedOrNoneTest {
    @TestCase
    func absentKeyReturnsNone() {
        // arrange
        let dms = DataModelStruct().add(field("present", 1))

        // act & assert
        @Assert(dms.getDeserializedOrNone<String>("missing").isNone())
    }

    @TestCase
    func presentKeyReturnsDeserializedValue() {
        // arrange
        let dms = DataModelStruct().add(field("id", "abc"))

        // act
        let result = dms.getDeserializedOrNone<IntegerOrString>("id")

        // assert
        @Assert(result.isSome())
        @Expect(IntegerOrString.String("abc"), result.getOrThrow())
    }

    @TestCase
    func presentNullIsDistinguishableFromAbsentViaNullable() {
        // arrange
        let dms = DataModelStruct().add(Field("id", DataModelNull()))

        // act - the optional-and-nullable shape: ?Nullable<T>
        let result = dms.getDeserializedOrNone<Nullable<IntegerOrString>>("id")

        // assert
        @Assert(result.isSome())
        @Assert(result.getOrThrow().isNull())
    }

    @TestCase
    func undeserializableValueThrows() {
        // arrange
        let dms = DataModelStruct().add(Field("id", DataModelStruct()))

        // act & assert
        @AssertThrows[DataModelException](dms.getDeserializedOrNone<IntegerOrString>("id"))
    }
}

@Test
class GetDeserializedOrThrowTest {
    @TestCase
    func presentKeyReturnsDeserializedValue() {
        // arrange
        let dms = DataModelStruct().add(field("id", 42))

        // act
        let result = dms.getDeserializedOrThrow<IntegerOrString>("id")

        // assert
        @Expect(IntegerOrString.Integer(42), result)
    }

    @TestCase
    func absentKeyThrows() {
        // arrange
        let dms = DataModelStruct().add(field("present", 1))

        // act
        let e = @AssertThrows[DataModelException](dms.getDeserializedOrThrow<String>("missing"))

        // assert
        @Expect("required field \"missing\" is absent", e.message)
    }

    @TestCase
    func presentNullThrowsFromTheDeserializer() {
        // arrange - present but null: it is the deserializer that rejects it, not the lookup
        let dms = DataModelStruct().add(Field("id", DataModelNull()))

        // act
        let e = @AssertThrows[DataModelException](dms.getDeserializedOrThrow<IntegerOrString>("id"))

        // assert
        @Expect("expected integer or string", e.message)
    }

    @TestCase
    func undeserializableValueThrows() {
        // arrange
        let dms = DataModelStruct().add(Field("id", DataModelSeq()))

        // act & assert
        @AssertThrows[DataModelException](dms.getDeserializedOrThrow<IntegerOrString>("id"))
    }
}

@Test
class AddFieldIfSomeTest {
    @TestCase
    func someIsWritten() {
        // arrange
        let dms = DataModelStruct()

        // act
        dms.addFieldIfSome("name", Some("cjls"))

        // assert
        @Expect("cjls", dms.getDeserializedOrThrow<String>("name"))
    }

    @TestCase
    func noneIsOmittedRatherThanWrittenAsNull() {
        // arrange
        let dms = DataModelStruct()

        // act
        dms.addFieldIfSome("name", None<String>)

        // assert - absent, not present-and-null
        @Assert(dms.getOrNone("name").isNone())
    }

    @TestCase
    func someNullableNullIsWrittenAsNull() {
        // arrange - the optional-and-nullable shape: Some(Null) must reach the wire as null
        let dms = DataModelStruct()

        // act
        dms.addFieldIfSome("id", Some(Nullable<IntegerOrString>.Null))

        // assert
        @Assert(dms.getOrThrow("id") is DataModelNull)
    }

    @TestCase
    func aBareDataModelTakesTheNonGenericOverload() {
        // arrange - `DataModel` is not `Serializable<DataModel>`, so a value that is
        // already one cannot reach the generic overload
        let dms = DataModelStruct()

        // act
        dms.addFieldIfSome("data", Some(DataModelString("extra")))

        // assert
        @Expect("{\"data\":\"extra\"}", dms.toJson().toString())
    }

    @TestCase
    func everyCallInAChainLandsOnTheSameStruct() {
        // act - each call returns the struct, so writing a whole object reads as one chain
        let dms = DataModelStruct()
            .add(field("first", 1))
            .addFieldIfSome("second", None<Int64>)
            .addFieldIfSome("third", Some(3))
            .addFieldIfSome("fourth", Some(DataModelString("4")))

        // assert - both overloads reached it, and the `None` wrote nothing
        @Expect(1, dms.getDeserializedOrThrow<Int64>("first"))
        @Expect(3, dms.getDeserializedOrThrow<Int64>("third"))
        @Expect("4", dms.getOrThrow("fourth").asStringOrThrow())
        @Assert(dms.getOrNone("second").isNone())
    }
}
