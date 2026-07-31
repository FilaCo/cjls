package stdxx

import std.unittest.*
import std.unittest.testmacro.*
import stdx.serialization.serialization.*

@Test
class GetOrNoneTest {
    func intOf(dm: DataModel): Int64 {
        (dm as DataModelInt).getOrThrow().getValue()
    }

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
        @Expect(42, intOf(result.getOrThrow()))
    }

    @TestCase
    func presentNullIsDistinctFromAbsent() {
        // arrange - key present with a null value
        let dms = DataModelStruct().add(Field("nullable", DataModelNull()))

        // act
        let result = dms.getOrNone("nullable")

        // assert - Some(DataModelNull), not None
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
        @Expect(2, intOf(result.getOrThrow()))
    }
}
