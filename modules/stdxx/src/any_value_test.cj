package stdxx

import std.collection.ArrayList
import std.unittest.*
import std.unittest.testmacro.*
import stdx.serialization.serialization.*

@Test
class AnyValueTest {
    @TestCase
    func whateverIsReadIsWrittenBackAsIs() {
        // arrange
        let dm = DataModelSeq(ArrayList<DataModel>([DataModelInt(1), DataModelNull()]))

        // act
        let written = AnyValue.deserialize(dm).serialize()

        // assert
        @Expect(refEq(dm, written))
    }

    @TestCase
    func nullIsAValueLikeAnyOther() {
        // act & assert
        @Expect(AnyValue.deserialize(DataModelNull()).data is DataModelNull)
    }
}
