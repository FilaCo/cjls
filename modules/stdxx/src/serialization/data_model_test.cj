package stdxx.serialization

import std.unittest.*
import std.unittest.testmacro.*
import stdx.serialization.serialization.*

@Test
class DataModelShapeTest {
    @TestCase
    func matchingShapesAreUnwrapped() {
        // act & assert
        @Expect(0, DataModelStruct().asStructOrThrow().getFields().size)
        @Expect(0, DataModelSeq().asSeqOrThrow().getItems().size)
        @Expect("hello", DataModelString("hello").asStringOrThrow())
        @Expect(42, DataModelInt(42).asIntOrThrow())
        @Expect(DataModelBool(true).asBoolOrThrow())
    }

    @TestCase
    func mismatchedShapesThrowNamingWhatWasWanted() {
        // act
        let onStruct = @AssertThrows[DataModelException](DataModelInt(1).asStructOrThrow())
        let onSeq = @AssertThrows[DataModelException](DataModelInt(1).asSeqOrThrow())
        let onString = @AssertThrows[DataModelException](DataModelInt(1).asStringOrThrow())
        let onInt = @AssertThrows[DataModelException](DataModelString("1").asIntOrThrow())
        let onBool = @AssertThrows[DataModelException](DataModelNull().asBoolOrThrow())

        // assert
        @Expect("expected `DataModelStruct`", onStruct.message)
        @Expect("expected `DataModelSeq`", onSeq.message)
        @Expect("expected `DataModelString`", onString.message)
        @Expect("expected `DataModelInt`", onInt.message)
        @Expect("expected `DataModelBool`", onBool.message)
    }
}

@Test
class DataModelFieldsReadTest {
    @TestCase
    func anAbsentKeyIsNoneAndAnExplicitNullIsNot() {
        // arrange
        let dms = DataModelStruct().add(Field("nullable", DataModelNull()))

        // act & assert
        @Expect(dms.getOrNone("missing").isNone())
        @Expect(dms.getOrNone("nullable").getOrThrow() is DataModelNull)
        @Expect(dms.getOrThrow("nullable") is DataModelNull)
    }

    @TestCase
    func aRepeatedKeyReadsAsItsLastValue() {
        // arrange
        let dms = DataModelStruct().add(field("k", 1)).add(field("k", 2))

        // act & assert
        @Expect(2, dms.getOrNone("k").getOrThrow().asIntOrThrow())
        @Expect(2, dms.getDeserializedOrThrow<Int64>("k"))
    }

    @TestCase
    func anAbsentRequiredKeyThrowsNamingIt() {
        // arrange
        let dms = DataModelStruct()

        // act
        let e = @AssertThrows[DataModelException](dms.getDeserializedOrThrow<String>("missing"))

        // assert
        @Expect("required field \"missing\" is absent", e.message)
    }

    @TestCase
    func getDeserializedOrNoneHandsAnExplicitNullToTheDeserializer() {
        // arrange
        let dms = DataModelStruct().add(Field("k", DataModelNull()))

        // act & assert - `Option` reads `null` as `None`, `String` refuses it
        @Expect(dms.getDeserializedOrNone<Option<String>>("missing").isNone())
        @Expect(dms.getDeserializedOrNone<Option<String>>("k").getOrThrow().isNone())
        @AssertThrows[DataModelException](dms.getDeserializedOrNone<String>("k"))
    }

    @TestCase[key in ["missing", "null"]]
    func getDeserializedOrNoneOnNullReadsAbsentAndNullAlike(key: String) {
        // arrange
        let dms = DataModelStruct().add(Field("null", DataModelNull()))

        // act & assert
        @Expect(dms.getDeserializedOrNoneOnNull<String>(key).isNone())
    }

    @TestCase
    func aValueOfTheWrongShapeThrows() {
        // arrange
        let dms = DataModelStruct().add(Field("k", DataModelSeq()))

        // act & assert
        @AssertThrows[DataModelException](dms.getDeserializedOrNone<String>("k"))
        @AssertThrows[DataModelException](dms.getDeserializedOrNoneOnNull<String>("k"))
        @AssertThrows[DataModelException](dms.getDeserializedOrThrow<String>("k"))
    }
}

@Test
class DataModelFieldsWriteTest {
    @TestCase
    func noneIsOmittedRatherThanWrittenAsNull() {
        // act
        let dms = DataModelStruct().addFieldIfSome("name", None<String>)

        // assert
        @Expect(dms.getOrNone("name").isNone())
    }

    @TestCase
    func everyCallInAChainLandsOnTheSameStruct() {
        // act - a bare `DataModel` is not `Serializable`, so it takes the non-generic overload
        let dms = DataModelStruct()
            .add(field("first", 1))
            .addFieldIfSome("second", None<Int64>)
            .addFieldIfSome("third", Some(3))
            .addFieldIfSome("fourth", Some(DataModelString("4")))

        // assert
        @Expect(1, dms.getDeserializedOrThrow<Int64>("first"))
        @Expect(dms.getOrNone("second").isNone())
        @Expect(3, dms.getDeserializedOrThrow<Int64>("third"))
        @Expect("4", dms.getOrThrow("fourth").asStringOrThrow())
    }
}
