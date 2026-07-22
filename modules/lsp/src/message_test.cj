package lsp

import std.collection.HashMap
import std.io.ByteBuffer
import stdx.encoding.json.stream.{JsonReader, JsonWriter}
import std.unittest.prop_test.*

@Test
class MessageSerializeTest {
    @Frozen
    func serialize(msg: Message): String {
        let bb = ByteBuffer()
        let jw = JsonWriter(bb)
        msg.toJson(jw)
        jw.flush()
        String.fromUtf8(bb.bytes())
    }

    @TestCase
    func serializeRequestWithoutParams() {
        // arrange
        let msg = Request(RequestMessage(Integer(1), "initialize"))

        // act
        let json = serialize(msg)

        // assert
        @Expect("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\"}", json)
    }

    @TestCase
    func serializeRequestWithParams() {
        // arrange
        let params = LspObject(HashMap([("processId", LspInteger(42))]))
        let msg = Request(RequestMessage(Integer(1), "initialize", params: params))

        // act
        let json = serialize(msg)

        // assert
        @Expect("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"processId\":42}}", json)
    }

    @TestCase
    func serializeRequestWithStringId() {
        // arrange
        let msg = Request(RequestMessage(IntegerOrString.String("abc"), "shutdown"))

        // act
        let json = serialize(msg)

        // assert
        @Expect("{\"jsonrpc\":\"2.0\",\"id\":\"abc\",\"method\":\"shutdown\"}", json)
    }

    @TestCase
    func serializeNotificationWithoutParams() {
        // arrange
        let msg = Notification(NotificationMessage("exit"))

        // act
        let json = serialize(msg)

        // assert
        @Expect("{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}", json)
    }

    @TestCase
    func serializeNotificationWithParams() {
        // arrange
        let params = LspString("hello")
        let msg = Notification(NotificationMessage("textDocument/didOpen", params: params))

        // act
        let json = serialize(msg)

        // assert
        @Expect("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":\"hello\"}", json)
    }

    @TestCase
    func serializeResponseOk() {
        // arrange
        let result = LspInteger(42)
        let msg = Response(ResponseMessage(Integer(1), Ok(result)))

        // act
        let json = serialize(msg)

        // assert
        @Expect("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":42}", json)
    }

    @TestCase
    func serializeResponseErrWithoutData() {
        // arrange
        let err = ResponseError(ErrorCode.ParseError, "parse error")
        let msg = Response(ResponseMessage(Integer(1), Err(err)))

        // act
        let json = serialize(msg)

        // assert
        @Expect(
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32700,\"message\":\"parse error\"}}", json)
    }

    @TestCase
    func serializeResponseErrWithData() {
        // arrange
        let data = LspString("extra")
        let err = ResponseError(ParseError, "parse error", data: data)
        let msg = Response(ResponseMessage(Integer(1), Err(err)))

        // act
        let json = serialize(msg)

        // assert
        @Expect(
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32700,\"message\":\"parse error\",\"data\":\"extra\"}}",
            json)
    }

    @TestCase
    func serializeResponseOkWithNullId() {
        // arrange
        let result = LspNull
        let msg = Response(ResponseMessage(None, Ok(result)))

        // act
        let json = serialize(msg)

        // assert
        @Expect("{\"jsonrpc\":\"2.0\",\"id\":null,\"result\":null}", json)
    }
}

@Test
class MessageDeserializeTest {
    @Frozen
    func deserialize(json: String): Message {
        let jr = JsonReader(ByteBuffer(json.toArray()))
        Message.fromJson(jr)
    }

    @TestCase
    func deserializeRequestWithoutParams() {
        // arrange
        let json = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\"}"

        // act
        let msg = deserialize(json)

        // assert
        if (let Request(req) <- msg) {
            @Expect(Integer(1), req.id)
            @Expect("initialize", req.method)
            @Assert(req.params.isNone())
        } else {
            @Fail("expected Request")
        }
    }

    @TestCase
    func deserializeRequestWithStringId() {
        // arrange
        let json = "{\"jsonrpc\":\"2.0\",\"id\":\"abc\",\"method\":\"shutdown\"}"

        // act
        let msg = deserialize(json)

        // assert
        if (let Request(req) <- msg) {
            @Expect(IntegerOrString.String("abc"), req.id)
            @Expect("shutdown", req.method)
        } else {
            @Fail("expected Request")
        }
    }

    @TestCase
    func deserializeRequestWithParams() {
        // arrange
        let json = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"processId\":42}}"

        // act
        let msg = deserialize(json)

        // assert
        if (let Request(req) <- msg) {
            if (let Some(LspObject(obj)) <- req.params) {
                if (let Some(LspInteger(n)) <- obj.get("processId")) {
                    @Expect(42, n)
                } else {
                    @Fail("expected LspInteger")
                }
            } else {
                @Fail("expected LspObject params")
            }
        } else {
            @Fail("expected Request")
        }
    }

    @TestCase
    func deserializeNotification() {
        // arrange
        let json = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}"

        // act
        let msg = deserialize(json)

        // assert
        if (let Notification(n) <- msg) {
            @Expect("exit", n.method)
            @Assert(n.params.isNone())
        } else {
            @Fail("expected Notification")
        }
    }

    @TestCase
    func deserializeResponseOk() {
        // arrange
        let json = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":42}"

        // act
        let msg = deserialize(json)

        // assert
        if (let Response(res) <- msg) {
            if (let Some(Integer(n)) <- res.id) {
                @Expect(1, n)
            } else {
                @Fail("expected Some(Integer) id")
            }
            if (let Ok(v) <- res.resultOrError) {
                match (v) {
                    case LspInteger(n) => @Expect(42, n)
                    case _ => @Fail("expected LspInteger result")
                }
            } else {
                @Fail("expected Ok result")
            }
        } else {
            @Fail("expected Response")
        }
    }

    @TestCase
    func deserializeResponseErr() {
        // arrange
        let json = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32700,\"message\":\"parse error\"}}"

        // act
        let msg = deserialize(json)

        // assert
        if (let Response(res) <- msg) {
            if (let Err(err) <- res.resultOrError) {
                @Expect(-32700, err.code.toInteger())
                @Expect("parse error", err.message)
                @Assert(err.data.isNone())
            } else {
                @Fail("expected Err")
            }
        } else {
            @Fail("expected Response")
        }
    }

    @TestCase
    func deserializeResponseErrWithData() {
        // arrange
        let json = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32700,\"message\":\"parse error\",\"data\":\"extra\"}}"

        // act
        let msg = deserialize(json)

        // assert
        if (let Response(res) <- msg) {
            if (let Err(err) <- res.resultOrError) {
                @Assert(err.data.isSome())
                match (err.data.getOrThrow()) {
                    case LspString(s) => @Expect("extra", s)
                    case _ => @Fail("expected LspString data")
                }
            } else {
                @Fail("expected Err")
            }
        } else {
            @Fail("expected Response")
        }
    }

    @TestCase
    func deserializeResponseWithNullId() {
        // arrange
        let json = "{\"jsonrpc\":\"2.0\",\"id\":null,\"result\":42}"

        // act
        let msg = deserialize(json)

        // assert
        if (let Response(res) <- msg) {
            @Assert(res.id.isNone())
            if (let Ok(v) <- res.resultOrError) {
                match (v) {
                    case LspInteger(n) => @Expect(42, n)
                    case _ => @Fail("expected LspInteger result")
                }
            } else {
                @Fail("expected Ok result")
            }
        } else {
            @Fail("expected Response")
        }
    }

    @TestCase
    func deserializeIgnoresUnknownFields() {
        // arrange
        let json = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"shutdown\",\"unknownField\":\"ignore\"}"

        // act
        let msg = deserialize(json)

        // assert
        if (let Request(req) <- msg) {
            @Expect("shutdown", req.method)
        } else {
            @Fail("expected Request")
        }
    }

    @TestCase
    func deserializeResponseWithBothResultAndErrorThrows() {
        // arrange
        let json = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":42,\"error\":{\"code\":-32700,\"message\":\"x\"}}"

        // act & assert
        @AssertThrows[IllegalStateException](deserialize(json))
    }

    @TestCase
    func deserializeNonObjectThrows() {
        // arrange
        let json = "42"

        // act & assert
        @AssertThrows[IllegalStateException](deserialize(json))
    }
}

@Test
class MessageRoundtripTest {
    @Frozen
    func roundtrip(msg: Message): Message {
        let bb = ByteBuffer()
        let jw = JsonWriter(bb)
        msg.toJson(jw)
        jw.flush()
        let jr = JsonReader(bb)
        Message.fromJson(jr)
    }

    @TestCase
    func roundtripRequest() {
        // arrange
        let params = LspObject(HashMap<String, LspAny>([("processId", LspInteger(42))]))
        let original = Request(RequestMessage(IntegerOrString.Integer(1), "initialize", params: params))

        // act
        let roundtripped = roundtrip(original)

        // assert
        if (let Request(req) <- roundtripped) {
            @Expect(IntegerOrString.Integer(1), req.id)
            @Expect("initialize", req.method)
            @Assert(req.params.isSome())
        } else {
            @Fail("expected Request")
        }
    }

    @TestCase
    func roundtripNotification() {
        // arrange
        let original = Notification(NotificationMessage("exit"))

        // act
        let roundtripped = roundtrip(original)

        // assert
        if (let Notification(n) <- roundtripped) {
            @Expect("exit", n.method)
        } else {
            @Fail("expected Notification")
        }
    }

    @TestCase
    func roundtripResponseErrWithData() {
        // arrange
        let err = ResponseError(ErrorCode.ParseError, "parse error", data: LspString("extra"))
        let original = Response(ResponseMessage(Some(IntegerOrString.Integer(1)), Err(err)))

        // act
        let roundtripped = roundtrip(original)

        // assert
        if (let Response(res) <- roundtripped) {
            if (let Err(e) <- res.resultOrError) {
                @Expect(-32700, e.code.toInteger())
                @Expect("parse error", e.message)
                @Assert(e.data.isSome())
            } else {
                @Fail("expected Err")
            }
        } else {
            @Fail("expected Response")
        }
    }
}

@Test
class ResponseErrorDeriveTest {
    @Frozen
    func serialize(err: ResponseError): String {
        let bb = ByteBuffer()
        let jw = JsonWriter(bb)
        err.toJson(jw)
        jw.flush()
        String.fromUtf8(bb.bytes())
    }

    @Frozen
    func deserialize(json: String): ResponseError {
        let jr = JsonReader(ByteBuffer(json.toArray()))
        ResponseError.fromJson(jr)
    }

    @TestCase
    func serializeErrorWithoutData() {
        // arrange
        let err = ResponseError(ErrorCode.ParseError, "parse error")

        // act
        let json = serialize(err)

        // assert
        @Expect("{\"code\":-32700,\"message\":\"parse error\"}", json)
    }

    @TestCase
    func serializeErrorWithData() {
        // arrange
        let err = ResponseError(ErrorCode.ParseError, "parse error", data: LspString("extra"))

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
        @Expect(-32700, err.code.toInteger())
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
        @Expect(-32700, err.code.toInteger())
        @Expect("parse error", err.message)
        @Assert(err.data.isSome())
        match (err.data.getOrThrow()) {
            case LspString(s) => @Expect("extra", s)
            case _ => @Fail("expected LspString data")
        }
    }

    @TestCase
    func roundtripErrorWithData() {
        // arrange
        let original = ResponseError(ErrorCode.ServerNotInitialized, "not ready", data: LspInteger(99))

        // act
        let json = serialize(original)
        let roundtripped = deserialize(json)

        // assert
        @Expect(-32002, roundtripped.code.toInteger())
        @Expect("not ready", roundtripped.message)
        @Assert(roundtripped.data.isSome())
        match (roundtripped.data.getOrThrow()) {
            case LspInteger(n) => @Expect(99, n)
            case _ => @Fail("expected LspInteger data")
        }
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
}

@Test
@Configure[randomSeed: 100500]
class MessagePropertyTest {
    @Frozen
    func roundtrip(msg: Message): Message {
        let bb = ByteBuffer()
        let jw = JsonWriter(bb)
        msg.toJson(jw)
        jw.flush()
        let jr = JsonReader(bb)
        Message.fromJson(jr)
    }

    // Property: serializing a Request and deserializing it back
    // preserves the integer id exactly.
    @TestCase[n in random()]
    func roundtripPreservesRequestId(n: Int64) {
        // arrange
        let original = Request(RequestMessage(IntegerOrString.Integer(n), "test"))

        // act
        let roundtripped = roundtrip(original)

        // assert
        if (let Request(req) <- roundtripped) {
            @Expect(IntegerOrString.Integer(n), req.id)
        } else {
            @Fail("expected Request")
        }
    }

    // Property: serializing a Response and deserializing it back
    // preserves both the integer id and the integer result exactly.
    @TestCase[n in random()]
    func roundtripPreservesResponseResult(n: Int64) {
        // arrange
        let id = IntegerOrString.Integer(n)
        let result = LspInteger(n)
        let original = Response(ResponseMessage(id, Ok(result)))

        // act
        let roundtripped = roundtrip(original)

        // assert
        if (let Response(res) <- roundtripped) {
            if (let Some(Integer(m)) <- res.id) {
                @Expect(n, m)
            } else {
                @Fail("expected Some(Integer) id")
            }
            if (let Ok(v) <- res.resultOrError) {
                match (v) {
                    case LspInteger(m) => @Expect(n, m)
                    case _ => @Fail("expected LspInteger result")
                }
            } else {
                @Fail("expected Ok result")
            }
        } else {
            @Fail("expected Response")
        }
    }
}
