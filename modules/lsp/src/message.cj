package lsp

import stdx.encoding.json.stream.*
import stdxx.deriving.*

public type RequestId = IntegerOrString

public class JsonRpcProtocolException <: LspException {
    init(msg: String) {
        super(msg)
    }
}

public enum Message <: JsonSerializable & JsonDeserializable<Message> & ToString {
    | Request(RequestMessage)
    | Notification(NotificationMessage)
    | Response(ResponseMessage)

    /**
     * @throws JsonRpcProtocolException - if got a malformed JSON
     */
    @Frozen
    public static func fromJson(r: JsonReader): Message {
        if (let Some(tok) <- r.peek() && tok == BeginObject) {
            var idSet = false
            var id = None<RequestId>
            var method = None<String>
            var params = None<LspAny>
            var responseResult = None<LspAny>
            var responseError = None<ResponseError>
            r.startObject()
            while (r.peek() != EndObject) {
                match (r.readName()) {
                    case "id" =>
                        id = r.readValue()
                        idSet = true
                    case "method" => method = r.readValue<String>()
                    case "params" => params = r.readValue()
                    case "result" => responseResult = r.readValue()
                    case "error" => responseError = r.readValue<ResponseError>()
                    case _ => r.skip()
                }
            }
            r.endObject()
            if (idSet) {
                match ((responseResult, responseError)) {
                    case (Some(_), Some(_)) => throw JsonRpcProtocolException("malformed response message")
                    case (Some(result), None) => return ResponseMessage(id, Ok(result)).enveloped()
                    case (None, Some(error)) => return ResponseMessage(id, Err(error)).enveloped()
                    case _ => return RequestMessage(id.getOrThrow(), method.getOrThrow(), params: params).enveloped()
                }
            }

            return NotificationMessage(method.getOrThrow(), params: params).enveloped()
        }

        throw JsonRpcProtocolException("unable to deserialize Message")
    }

    @Frozen
    public func toJson(w: JsonWriter): Unit {
        // DO NOT use variant data structures `toJson` implementation - it will lead to an infinite recursion
        w.startObject()
        w.writeJsonRpcField()

        match (this) {
            case Request(req) =>
                w.writeName("id").writeValue(req.id).writeName("method").writeValue(req.method)

                if (let Some(p) <- req.params) {
                    w.writeName("params").writeValue(p)
                }
            case Notification(n) =>
                w.writeName("method").writeValue(n.method)

                if (let Some(p) <- n.params) {
                    w.writeName("params").writeValue(p)
                }
            case Response(res) =>
                w.writeName("id").writeValue(res.id)

                match (res.resultOrError) {
                    case Ok(v) => w.writeName("result").writeValue(v)
                    case Err(err) => w.writeName("error").writeValue(err)
                }
        }

        w.endObject()
    }

    @Frozen
    public func toString(): String {
        toJsonString(this)
    }
}

public struct RequestMessage <: JsonSerializable & ToString {
    @Frozen
    public RequestMessage(
        public let id: RequestId,
        /**
         * The method to be invoked.
         */
        public let method: String,
        /**
         * The method's params.
         */
        public let params!: ?LspAny = None
    ) {}

    @Frozen
    public func toJson(w: JsonWriter): Unit {
        Request(this).toJson(w)
    }

    @Frozen
    public func toString(): String {
        toJsonString(this)
    }

    @Frozen
    public prop isInitialize: Bool {
        get() {
            method == "initialize"
        }
    }

    @Frozen
    public prop isShutdown: Bool {
        get() {
            method == "shutdown"
        }
    }

    @Frozen
    public func enveloped(): Message {
        Request(this)
    }

    /**
     * @throws MethodMistmatchException
     */
    @Frozen
    public func extract<P>(method: String): P where P <: JsonDeserializable<P> {
        if (this.method != method) {
            throw MethodMismatchException(this.method, method)
        }
        fromLspAny(params.getOrDefault {=> LspNull})
    }
}

public struct NotificationMessage <: JsonSerializable & ToString {
    @Frozen
    public NotificationMessage(
        /**
         * The method to be invoked.
         */
        public let method: String,
        /**
         * The method's params.
         */
        public let params!: ?LspAny = None
    ) {}

    @Frozen
    public func toJson(w: JsonWriter): Unit {
        Notification(this).toJson(w)
    }

    @Frozen
    public func toString(): String {
        toJsonString(this)
    }

    @Frozen
    public prop isInitialized: Bool {
        get() {
            method == "initialized"
        }
    }

    @Frozen
    public prop isExit: Bool {
        get() {
            method == "exit"
        }
    }

    @Frozen
    public func enveloped(): Message {
        Notification(this)
    }

    /**
     * @throws MethodMistmatchException
     */
    @Frozen
    public func extract<P>(method: String): P where P <: JsonDeserializable<P> {
        if (this.method != method) {
            throw MethodMismatchException(this.method, method)
        }
        fromLspAny(params.getOrDefault {=> LspNull})
    }
}

public class MethodMismatchException <: LspException {
    @Frozen
    public MethodMismatchException(expectedMethod: String, actualMethod: String) {
        super("Unable to extract params, expected method: `${expectedMethod}`, got: ${actualMethod}")
    }
}

public struct ResponseMessage <: JsonSerializable & ToString {
    @Frozen
    public ResponseMessage(public let id: ?RequestId, public let resultOrError: ResponseResult) {}

    @Frozen
    public static func initOk<R>(id: RequestId, result: R): ResponseMessage where R <: JsonSerializable {
        ResponseMessage(id, Ok(toLspAny(result)))
    }

    @Frozen
    public static func initErr(id: RequestId, code: ErrorCode, message: String): ResponseMessage {
        let error = ResponseError(code, message)
        ResponseMessage(id, Err(error))
    }

    @Frozen
    public func toJson(w: JsonWriter): Unit {
        Response(this).toJson(w)
    }

    @Frozen
    public func toString(): String {
        toJsonString(this)
    }

    @Frozen
    public func enveloped(): Message {
        Response(this)
    }
}

public enum ResponseResult {
    | Ok(LspAny)
    | Err(ResponseError)
}

@DeriveExt[Json]
public struct ResponseError <: ToString {
    public ResponseError(
        /**
         * A number indicating the error type that occurred.
         */
        public let code: ErrorCode,
        /**
         * A string providing a short description of the error.
         */
        public let message: String,
        /**
         * A primitive or structured value that contains additional
         * information about the error. Can be omitted.
         */
        public let data!: ?LspAny = None) {}

    @Frozen
    public func toString(): String {
        toJsonString(this)
    }
}

public enum ErrorCode <: JsonSerializable & JsonDeserializable<ErrorCode> & ToString {
    // Defined by JSON RPC:
    | ParseError
    | InvalidRequest
    | MethodNotFound
    | InvalidParams
    | InternalError
    /**
     * Error code indicating that a server received a notification or
     * request before the server received the `initialize` request.
     */
    | ServerNotInitialized
    | UnknownErrorCode

    @Frozen
    public static func fromInteger(v: Int64): ErrorCode {
        match (v) {
            case -32700 => ParseError
            case -32600 => InvalidRequest
            case -32601 => MethodNotFound
            case -32602 => InvalidParams
            case -32603 => InternalError
            case -32002 => ServerNotInitialized
            case _ => UnknownErrorCode
        }
    }

    @Frozen
    public func toInteger(): Int64 {
        match (this) {
            case ParseError => -32700
            case InvalidRequest => -32600
            case MethodNotFound => -32601
            case InvalidParams => -32602
            case InternalError => -32603
            case ServerNotInitialized => -32002
            case UnknownErrorCode => -32001
        }
    }

    @Frozen
    public static func fromJson(r: JsonReader): ErrorCode {
        if (let Some(tok) <- r.peek() && tok == JsonNumber) {
            return fromInteger(r.readValue<Int64>())
        }

        throw IllegalStateException("unable to deserialize error code")
    }

    @Frozen
    public func toJson(w: JsonWriter): Unit {
        w.writeValue(toInteger())
    }

    @Frozen
    public func toString(): String {
        toJsonString(this)
    }
}
