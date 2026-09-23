package stdxx

import std.unittest.*
import std.unittest.testmacro.*
import stdx.serialization.serialization.*

@Test
class ArrayOrObjectTest {
    @TestCase
    func deserializeStructYieldsObject() {
        // arrange
        let dm = DataModelStruct().add(field("processId", 42))

        // act
        let restored = ArrayOrObject.deserialize(dm)

        // assert
        @Assert(restored.isObject())
        let restoredFieldDm = restored.getObjectOrThrow().get("processId")
        @Assert(restoredFieldDm is DataModelInt)
        @Assert(42, (restoredFieldDm as DataModelInt).getOrThrow().getValue())
    }

    @TestCase
    func deserializeSeqYieldsArray() {
        // arrange
        let seq = DataModelSeq()
        seq.add(DataModelInt(7))
        let dm: DataModel = seq

        // act
        let restored = ArrayOrObject.deserialize(dm)

        // assert
        @Assert(restored.isArray())
    }

    @TestCase
    func deserializeScalarThrows() {
        // arrange - a bare int is neither array nor object
        let dm = DataModelInt(42)

        // act & assert
        @AssertThrows[DataModelException](ArrayOrObject.deserialize(dm))
    }

    @TestCase
    func getArrayOnObjectThrows() {
        // arrange
        let sut = ArrayOrObject.Object(DataModelStruct())

        // act
        let e = @AssertThrows[UnexpectedVariantException](sut.getArrayOrThrow())

        // assert
        @Expect("expected `Array` variant, got `Object`", e.message)
    }

    @TestCase
    func getObjectOnArrayThrows() {
        // arrange
        let sut = ArrayOrObject.Array(DataModelSeq())

        // act
        let e = @AssertThrows[UnexpectedVariantException](sut.getObjectOrThrow())

        // assert
        @Expect("expected `Object` variant, got `Array`", e.message)
    }
}
