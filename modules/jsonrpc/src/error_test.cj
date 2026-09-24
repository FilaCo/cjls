package jsonrpc

import std.unittest.*
import std.unittest.testmacro.*
import std.unittest.prop_test.*
import stdx.encoding.json.*
import stdx.serialization.serialization.*
import stdxx.serialization.*

@Test
class ResponseErrorTest {
    func errorOf(json: String): ResponseError {
        ResponseError.deserialize(DataModel.fromJson(JsonValue.fromStr(json)))
    }

    @TestCase[json in [
        ##"{"code":-32700,"message":"parse error"}"##,
        ##"{"code":-32700,"message":"parse error","data":"extra"}"##,
        ##"{"code":1,"message":"m","data":{"a":[1,null]}}"##
    ]]
    func anErrorReadsBackAsItWasWritten(json: String) {
        // act
        let written = errorOf(json).serialize().toJson().toString()

        // assert
        @Expect(json, written)
    }

    @TestCase[json in [ "42", "\"boom\"", "[-32700]", "null", ##"{"message":"m"}"##, ##"{"code":-32700}"## ]]
    func anErrorWithoutCodeAndMessageDoesNotRead(json: String) {
        // act & assert
        @AssertThrows[DataModelException](errorOf(json))
    }
}

@Test
@Configure[randomSeed: 100500]
class ErrorCodeTest {
    @TestCase[value in random()]
    func anyCodeSurvivesARoundTrip(value: Int32) {
        // arrange - the codes are open, so one this side has no constant for is kept as is
        let code = ErrorCode(value)

        // act
        let written = code.serialize()

        // assert
        @Expect(code, ErrorCode.deserialize(written))
        @Expect(Int64(value), written.asIntOrThrow())
        @Expect(value.toString(), code.toString())
    }

    @TestCase
    func aCodeThatIsNoInt32DoesNotRead() {
        // act & assert
        @AssertThrows[DataModelException](ErrorCode.deserialize(DataModelString("-32700")))
        @AssertThrows[DataModelException](ErrorCode.deserialize(DataModelInt(9999999999)))
    }
}
