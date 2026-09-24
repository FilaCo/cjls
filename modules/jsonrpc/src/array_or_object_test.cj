package jsonrpc

import std.unittest.*
import std.unittest.testmacro.*
import stdx.serialization.serialization.*
import stdxx.UnexpectedVariantException

@Test
class ArrayOrObjectTest {
    @TestCase[dm in [DataModelSeq(), DataModelStruct().add(field("k", 1))]]
    func aStructuredValueIsWrittenBackAsIs(dm: DataModel) {
        // act
        let written = ArrayOrObject.deserialize(dm).serialize()

        // assert
        @Expect(refEq(dm, written))
    }

    @TestCase[dm in [DataModelInt(42), DataModelString("s"), DataModelNull()]]
    func aScalarIsRefused(dm: DataModel) {
        // act & assert
        @AssertThrows[DataModelException](ArrayOrObject.deserialize(dm))
    }

    @TestCase
    func askingForTheOtherVariantThrows() {
        // act
        let onObject = @AssertThrows[UnexpectedVariantException](ArrayOrObject.Object(DataModelStruct()).getArrayOrThrow())
        let onArray = @AssertThrows[UnexpectedVariantException](ArrayOrObject.Array(DataModelSeq()).getObjectOrThrow())

        // assert
        @Expect("expected `Array` variant, got `Object`", onObject.message)
        @Expect("expected `Object` variant, got `Array`", onArray.message)
    }
}
