package jsonrpc

import std.unittest.*
import std.unittest.testmacro.*
import stdx.encoding.json.*
import stdx.serialization.serialization.*
import stdxx.{IntegerOrString, UnexpectedVariantException}
import stdxx.serialization.*

func fieldOf(params: ?ArrayOrObject, name: String): DataModel {
    params.getOrThrow().getObjectOrThrow().get(name)
}

func bodyOf(json: String): Body {
    Body.deserialize(DataModel.fromJson(JsonValue.fromStr(json)))
}

@Test
class BodyCodecTest {
    // The shape is the discriminator, so reading a frame as the wrong variant writes it back
    // with other keys: a round trip pins the variant as well as every field.
    @TestCase[json in [
        ##"{"jsonrpc":"2.0","id":1,"method":"m"}"##,
        ##"{"jsonrpc":"2.0","id":"abc","method":"m"}"##,
        ##"{"jsonrpc":"2.0","id":1,"method":"m","params":{"a":42}}"##,
        ##"{"jsonrpc":"2.0","id":1,"method":"m","params":[1,2]}"##,
        ##"{"jsonrpc":"2.0","method":"m"}"##,
        ##"{"jsonrpc":"2.0","method":"m","params":{"a":"b"}}"##,
        ##"{"jsonrpc":"2.0","id":1,"result":42}"##,
        ##"{"jsonrpc":"2.0","id":1,"result":null}"##,
        ##"{"jsonrpc":"2.0","id":null,"result":42}"##,
        ##"{"jsonrpc":"2.0","id":1,"error":{"code":-32700,"message":"parse error"}}"##,
        ##"{"jsonrpc":"2.0","id":1,"error":{"code":1,"message":"m","data":{"a":[1]}}}"##
    ]]
    func aMessageReadsBackAsItWasWritten(json: String) {
        // act
        let written = bodyOf(json).serialize().toJson().toString()

        // assert
        @Expect(json, written)
    }

    @TestCase
    func anUnknownFieldIsIgnored() {
        // act
        let body = bodyOf(##"{"jsonrpc":"2.0","id":1,"method":"m","unknown":"x"}"##)

        // assert
        @Expect("m", body.getRequestBodyOrThrow().method)
    }

    @TestCase[json in [
        ##"{"method":"m"}"##,
        ##"{"jsonrpc":"1.0","method":"m"}"##,
        ##"{"jsonrpc":2.0,"method":"m"}"##,
        ##"{"jsonrpc":null,"method":"m"}"##,
        ##"{"jsonrpc":"2.0.0","id":1,"method":"m"}"##
    ]]
    func aWrongProtocolVersionIsAnInvalidRequest(json: String) {
        // act
        let e = @AssertThrows[RpcException](bodyOf(json))

        // assert
        @Expect(ErrorCode.INVALID_REQUEST, e.code)
    }

    @TestCase
    func aResponseWithBothResultAndErrorIsAnInvalidRequest() {
        // arrange
        let json = ##"{"jsonrpc":"2.0","id":1,"result":42,"error":{"code":-32700,"message":"x"}}"##

        // act
        let e = @AssertThrows[RpcException](bodyOf(json))

        // assert
        @Expect(ErrorCode.INVALID_REQUEST, e.code)
    }

    @TestCase
    func aGetterOfTheWrongVariantNamesBoth() {
        // arrange
        let request = RequestBody(Integer(1), "m").enveloped()
        let notification = NotificationBody("m").enveloped()
        let response = ResponseBody(Value(Integer(1)), Result(DataModelNull())).enveloped()

        // act
        let onRequest = @AssertThrows[UnexpectedVariantException](request.getResponseBodyOrThrow())
        let onNotification = @AssertThrows[UnexpectedVariantException](notification.getRequestBodyOrThrow())
        let onResponse = @AssertThrows[UnexpectedVariantException](response.getNotificationBodyOrThrow())

        // assert
        @Expect("expected `Response` variant, got `Request`", onRequest.message)
        @Expect("expected `Request` variant, got `Notification`", onNotification.message)
        @Expect("expected `Notification` variant, got `Response`", onResponse.message)
    }
}

@Test
class ResultOrErrorTest {
    @TestCase
    func aGetterOfTheWrongVariantNamesBoth() {
        // arrange
        let result = ResultOrError.Result(DataModelNull())
        let error = ResultOrError.Error(ResponseError(ErrorCode.PARSE_ERROR, "parse error"))

        // act
        let onError = @AssertThrows[UnexpectedVariantException](error.getResultOrThrow())
        let onResult = @AssertThrows[UnexpectedVariantException](result.getErrorOrThrow())

        // assert
        @Expect("expected `Result` variant, got `Error`", onError.message)
        @Expect("expected `Error` variant, got `Result`", onResult.message)
    }
}
