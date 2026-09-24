package stdxx.serialization

import std.collection.ArrayList
import std.unittest.*
import std.unittest.testmacro.*
import stdx.serialization.serialization.*

@Test
class AnyValueTest {
    @TestCase[dm in [
        DataModelNull(),
        DataModelSeq(ArrayList<DataModel>([DataModelInt(1), DataModelNull()])),
        DataModelStruct().add(field("k", "v"))
    ]]
    func whateverIsReadIsWrittenBackAsIs(dm: DataModel) {
        // act
        let written = AnyValue.deserialize(dm).serialize()

        // assert
        @Expect(refEq(dm, written))
    }
}
