package jsonrpc

import std.unittest.*
import std.unittest.testmacro.*
import stdx.encoding.json.*
import stdx.serialization.serialization.*

func strOf(dm: DataModel): String {
    (dm as DataModelString).getOrThrow().getValue()
}

@Test
class ResponseErrorSerializeTest {
    func serialize(err: ResponseError): String {
        err.serialize().toJson().toString()
    }

    func deserialize(json: String): ResponseError {
        ResponseError.deserialize(DataModel.fromJson(JsonValue.fromStr(json)))
    }

    @TestCase
    func serializeErrorWithoutData() {
        // arrange
        let err = ResponseError(ErrorCode.PARSE_ERROR, "parse error")

        // act
        let json = serialize(err)

        // assert
        @Expect("{\"code\":-32700,\"message\":\"parse error\"}", json)
    }

    @TestCase
    func serializeErrorWithData() {
        // arrange
        let err = ResponseError(ErrorCode.PARSE_ERROR, "parse error", data: DataModelString("extra"))

        // act
        let json = serialize(err)

        // assert
        @Expect("{\"code\":-32700,\"message\":\"parse error\",\"data\":\"extra\"}", json)
    }

    @TestCase
    func deserializeErrorWithoutData() {
        // arrange
        let json = "{\"code\":-32700,\"message\":\"parse error\"}"

        // act
        let err = deserialize(json)

        // assert
        @Expect(ErrorCode.PARSE_ERROR, err.code)
        @Expect("parse error", err.message)
        @Assert(err.data.isNone())
    }

    @TestCase
    func deserializeErrorWithData() {
        // arrange
        let json = "{\"code\":-32700,\"message\":\"parse error\",\"data\":\"extra\"}"

        // act
        let err = deserialize(json)

        // assert
        @Expect(ErrorCode.PARSE_ERROR, err.code)
        @Expect("parse error", err.message)
        @Assert(err.data.isSome())
        @Expect("extra", strOf(err.data.getOrThrow()))
    }

    @TestCase
    func deserializeErrorMissingCodeThrows() {
        // arrange
        let json = "{\"message\":\"no code\"}"

        // act & assert
        @AssertThrows[Exception](deserialize(json))
    }

    @TestCase
    func deserializeErrorMissingMessageThrows() {
        // arrange
        let json = "{\"code\":-32700}"

        // act & assert
        @AssertThrows[Exception](deserialize(json))
    }

    @TestCase[json in [ "42", "\"boom\"", "[-32700]", "null" ]]
    func deserializeNonObjectErrorThrows(json: String) {
        // arrange - the "error" member must be an object; a bare scalar or array
        // is rejected before any field lookup happens.

        // act
        let e = @AssertThrows[DataModelException](deserialize(json))

        // assert
        @Expect("expected `DataModelStruct`", e.message)
    }
}

@Test
class ErrorCodeTest {
    // `deserialize` only accepts a `DataModelInt`, so a passing round trip also
    // pins that `serialize` produced one carrying `value`.
    @TestCase[value in [ 0, 42, - 1, - 32700, - 32000, 2147483647, - 2147483648 ]]
    func roundTrip(value: Int32) {
        // arrange
        let original = ErrorCode(value)

        // act
        let restored = ErrorCode.deserialize(original.serialize())

        // assert
        @Expect(original, restored)
        @Expect(Int64(value), intOf(original.serialize()))
    }

    @TestCase
    func deserializeRejectsNonInt() {
        // arrange
        let dm = DataModelString("-32700")

        // act & assert
        @AssertThrows[DataModelException](ErrorCode.deserialize(dm))
    }

    @TestCase
    func deserializeRejectsOutOfInt32Range() {
        // arrange - larger than Int32 can hold
        let dm = DataModelInt(9999999999)

        // act & assert
        @AssertThrows[DataModelException](ErrorCode.deserialize(dm))
    }

    @TestCase
    func standardCodesHaveExpectedValues() {
        // act & assert
        @Expect(-32700, ErrorCode.PARSE_ERROR.value)
        @Expect(-32600, ErrorCode.INVALID_REQUEST.value)
        @Expect(-32601, ErrorCode.METHOD_NOT_FOUND.value)
        @Expect(-32602, ErrorCode.INVALID_PARAMS.value)
        @Expect(-32603, ErrorCode.INTERNAL_ERROR.value)
        @Expect(-32002, ErrorCode.SERVER_NOT_INITIALIZED.value)
        @Expect(-32001, ErrorCode.UNKNOWN_ERROR_CODE.value)
    }

    @TestCase
    func equalityAndToString() {
        // act & assert
        @Expect(ErrorCode.PARSE_ERROR, ErrorCode(-32700))
        @Assert(ErrorCode.PARSE_ERROR != ErrorCode.INTERNAL_ERROR)
        @Expect("-32700", ErrorCode.PARSE_ERROR.toString())
    }
}
