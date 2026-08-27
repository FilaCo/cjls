package jsonrpc

import std.unittest.*
import std.unittest.testmacro.*
import stdx.encoding.json.*
import stdx.serialization.serialization.*
import stdxx.*

func fieldOf(params: ?ArrayOrObject, name: String): DataModel {
    params.getOrThrow().getObjectOrThrow().get(name)
}

@Test
class BodySerializeTest {
    func toJsonString(body: Body): String {
        body.serialize().toJson().toString()
    }

    @TestCase
    func serializeRequestWithoutParams() {
        // arrange
        let body = RequestBody(Integer(1), "initialize").enveloped()

        // act
        let json = toJsonString(body)

        // assert
        @Expect("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\"}", json)
    }

    @TestCase
    func serializeRequestWithParams() {
        // arrange
        let params = ArrayOrObject.Object(DataModelStruct().add(field("processId", 42)))
        let body = RequestBody(Integer(1), "initialize", params: params).enveloped()

        // act
        let json = toJsonString(body)

        // assert
        @Expect("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"processId\":42}}", json)
    }

    @TestCase
    func serializeRequestWithStringId() {
        // arrange
        let body = RequestBody(IntegerOrString.String("abc"), "shutdown").enveloped()

        // act
        let json = toJsonString(body)

        // assert
        @Expect("{\"jsonrpc\":\"2.0\",\"id\":\"abc\",\"method\":\"shutdown\"}", json)
    }

    @TestCase
    func serializeRequestWithArrayParams() {
        // arrange
        let seq = DataModelSeq()
        seq.add(DataModelInt(1))
        seq.add(DataModelInt(2))
        let params = ArrayOrObject.Array(seq)
        let body = RequestBody(Integer(1), "custom/positional", params: params).enveloped()

        // act
        let json = toJsonString(body)

        // assert
        @Expect("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"custom/positional\",\"params\":[1,2]}", json)
    }

    @TestCase
    func serializeNotificationWithoutParams() {
        // arrange
        let body = NotificationBody("exit").enveloped()

        // act
        let json = toJsonString(body)

        // assert
        @Expect("{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}", json)
    }

    @TestCase
    func serializeNotificationWithParams() {
        // arrange
        let params = ArrayOrObject.Object(DataModelStruct().add(field("uri", "file:///a.cj")))
        let body = NotificationBody("textDocument/didOpen", params: params).enveloped()

        // act
        let json = toJsonString(body)

        // assert
        @Expect("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"uri\":\"file:///a.cj\"}}", json)
    }

    @TestCase
    func serializeResponseResult() {
        // arrange
        let body = ResponseBody.result(Value(Integer(1)), 42).enveloped()

        // act
        let json = toJsonString(body)

        // assert
        @Expect("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":42}", json)
    }

    @TestCase
    func serializeResponseErrWithoutData() {
        // arrange
        let err = ResponseError(ErrorCode.PARSE_ERROR, "parse error")
        let body = ResponseBody.error(Value(Integer(1)), err).enveloped()

        // act
        let json = toJsonString(body)

        // assert
        @Expect("{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32700,\"message\":\"parse error\"}}", json)
    }

    @TestCase
    func serializeResponseWithNullId() {
        // arrange
        let body = ResponseBody.result(Null, DataModelNull()).enveloped()

        // act
        let json = toJsonString(body)

        // assert
        @Expect("{\"jsonrpc\":\"2.0\",\"id\":null,\"result\":null}", json)
    }
}

@Test
class BodyDeserializeTest {
    func deserialize(json: String): Body {
        Body.deserialize(DataModel.fromJson(JsonValue.fromStr(json)))
    }

    @TestCase
    func deserializeRequestWithoutParams() {
        // arrange
        let json = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\"}"

        // act
        let body = deserialize(json)

        // assert
        @Assert(body.isRequest())
        let req = body.getRequestBodyOrThrow()
        @Expect(Integer(1), req.id)
        @Expect("initialize", req.method)
        @Assert(req.params.isNone())
    }

    @TestCase
    func deserializeRequestWithStringId() {
        // arrange
        let json = "{\"jsonrpc\":\"2.0\",\"id\":\"abc\",\"method\":\"shutdown\"}"

        // act
        let body = deserialize(json)

        // assert
        @Assert(body.isRequest())
        let req = body.getRequestBodyOrThrow()
        @Expect(IntegerOrString.String("abc"), req.id)
        @Expect("shutdown", req.method)
    }

    @TestCase
    func deserializeRequestWithParams() {
        // arrange
        let json = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"processId\":42}}"

        // act
        let body = deserialize(json)

        // assert
        @Assert(body.isRequest())
        let req = body.getRequestBodyOrThrow()
        @Expect(42, fieldOf(req.params, "processId").asIntOrThrow())
    }

    @TestCase
    func deserializeNotification() {
        // arrange
        let json = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}"

        // act
        let body = deserialize(json)

        // assert
        @Assert(body.isNotification())
        let note = body.getNotificationBodyOrThrow()
        @Expect("exit", note.method)
        @Assert(note.params.isNone())
    }

    @TestCase
    func deserializeResponseResult() {
        // arrange
        let json = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":42}"

        // act
        let body = deserialize(json)

        // assert
        @Assert(body.isResponse())
        let res = body.getResponseBodyOrThrow()
        @Expect(Integer(1), res.id.getOrThrow())
        @Expect(42, res.resultOrError.getResultOrThrow().asIntOrThrow())
    }

    @TestCase
    func deserializeResponseError() {
        // arrange
        let json = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32700,\"message\":\"parse error\"}}"

        // act
        let body = deserialize(json)

        // assert
        @Assert(body.isResponse())
        let err = body.getResponseBodyOrThrow().resultOrError.getErrorOrThrow()
        @Expect(ErrorCode.PARSE_ERROR, err.code)
        @Expect("parse error", err.message)
        @Assert(err.data.isNone())
    }

    @TestCase
    func deserializeResponseWithNullId() {
        // arrange
        let json = "{\"jsonrpc\":\"2.0\",\"id\":null,\"result\":42}"

        // act
        let body = deserialize(json)

        // assert
        @Assert(body.isResponse())
        let res = body.getResponseBodyOrThrow()
        @Assert(res.id.isNull())
        @Expect(42, res.resultOrError.getResultOrThrow().asIntOrThrow())
    }

    @TestCase
    func deserializeIgnoresUnknownFields() {
        // arrange
        let json = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"shutdown\",\"unknownField\":\"ignore\"}"

        // act
        let body = deserialize(json)

        // assert
        @Assert(body.isRequest())
        @Expect("shutdown", body.getRequestBodyOrThrow().method)
    }

    @TestCase
    func deserializeResponseWithBothResultAndErrorThrows() {
        // arrange
        let json = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":42,\"error\":{\"code\":-32700,\"message\":\"x\"}}"

        // act & assert
        @AssertThrows[RpcException](deserialize(json))
    }

    @TestCase
    func deserializeNonObjectThrows() {
        // arrange
        let json = "42"

        // act & assert
        @AssertThrows[DataModelException](deserialize(json))
    }
}

@Test
class BodyAccessorTest {
    let request = RequestBody(Integer(1), "initialize").enveloped()
    let notification = NotificationBody("exit").enveloped()
    let response = ResponseBody.result(Value(Integer(1)), DataModelInt(42)).enveloped()

    @TestCase
    func predicatesMatchTheVariant() {
        // act & assert
        @Assert(request.isRequest())
        @Assert(notification.isNotification())
        @Assert(response.isResponse())
        @Assert(!request.isNotification())
        @Assert(!notification.isResponse())
        @Assert(!response.isRequest())
    }

    @TestCase
    func getRequestBodyNamesTheActualVariant() {
        // act
        let onNotification = @AssertThrows[UnexpectedVariantException](notification.getRequestBodyOrThrow())
        let onResponse = @AssertThrows[UnexpectedVariantException](response.getRequestBodyOrThrow())

        // assert
        @Expect("expected `Request` variant, got `Notification`", onNotification.message)
        @Expect("expected `Request` variant, got `Response`", onResponse.message)
    }

    @TestCase
    func getNotificationBodyNamesTheActualVariant() {
        // act
        let onRequest = @AssertThrows[UnexpectedVariantException](request.getNotificationBodyOrThrow())
        let onResponse = @AssertThrows[UnexpectedVariantException](response.getNotificationBodyOrThrow())

        // assert
        @Expect("expected `Notification` variant, got `Request`", onRequest.message)
        @Expect("expected `Notification` variant, got `Response`", onResponse.message)
    }

    @TestCase
    func getResponseBodyNamesTheActualVariant() {
        // act
        let onRequest = @AssertThrows[UnexpectedVariantException](request.getResponseBodyOrThrow())
        let onNotification = @AssertThrows[UnexpectedVariantException](notification.getResponseBodyOrThrow())

        // assert
        @Expect("expected `Response` variant, got `Request`", onRequest.message)
        @Expect("expected `Response` variant, got `Notification`", onNotification.message)
    }
}

@Test
class ResultOrErrorAccessorTest {
    let result = ResultOrError.Result(DataModelInt(42))
    let error = ResultOrError.Error(ResponseError(ErrorCode.PARSE_ERROR, "parse error"))

    @TestCase
    func predicatesMatchTheVariant() {
        // act & assert
        @Assert(result.isResult())
        @Assert(error.isError())
        @Assert(!result.isError())
        @Assert(!error.isResult())
    }

    @TestCase
    func getResultOnErrorThrows() {
        // act
        let e = @AssertThrows[UnexpectedVariantException](error.getResultOrThrow())

        // assert
        @Expect("expected `Result` variant, got `Error`", e.message)
    }

    @TestCase
    func getErrorOnResultThrows() {
        // act
        let e = @AssertThrows[UnexpectedVariantException](result.getErrorOrThrow())

        // assert
        @Expect("expected `Error` variant, got `Result`", e.message)
    }
}
