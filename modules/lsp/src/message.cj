package lsp

import stdx.encoding.json.stream.*
import stdxx.deriving.*

public type RequestId = IntegerOrString

public enum Message <: JsonSerializable & JsonDeserializable<Message> {
    | Request(RequestMessage)
    | Notification(NotificationMessage)
    | Response(ResponseMessage)

    @Frozen
    public static func fromJson(r: JsonReader): Message {
        if (let Some(tok) <- r.peek() && tok == BeginObject) {
            var id = None<RequestId>
            var method = None<String>
            var params = None<LspAny>
            var responseResult = None<LspAny>
            var responseError = None<ResponseError>
            r.startObject()
            while (r.peek() != EndObject) {
                match (r.readName()) {
                    case "id" => id = r.readValue()
                    case "method" => method = r.readValue()
                    case "params" => params = r.readValue()
                    case "result" => responseResult = r.readValue()
                    case "error" => responseError = r.readValue()
                    case _ => r.skip()
                }
            }
            r.endObject()
            if (let Some(id) <- id) {
                match ((responseResult, responseError)) {
                    case (Some(_), Some(_)) => throw IllegalStateException("malformed response message")
                    case (Some(result), None) => return Response(ResponseMessage(id, Ok(result)))
                    case (None, Some(error)) => return Response(ResponseMessage(id, Err(error)))
                    case _ => return Request(RequestMessage(id, method.getOrThrow(), params: params))
                }
            }

            return Notification(NotificationMessage(method.getOrThrow(), params: params))
        }

        throw IllegalStateException("unable to deserialize Message")
    }

    @Frozen
    public func toJson(w: JsonWriter): Unit {
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
}

public struct RequestMessage {
    @Frozen
    public RequestMessage(
        public let id: RequestId,
        /**
         * The method to be invoked.
         */
        public let method: String,
        /**
         * The method's params.
         * @note optional field
         */
        public let params!: ?LspAny = None
    ) {}
}

public struct NotificationMessage {
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
}

public struct ResponseMessage {
    @Frozen
    public ResponseMessage(public let id: ?RequestId, public let resultOrError: ResponseResult) {}
}

public enum ResponseResult {
    | Ok(LspAny)
    | Err(ResponseError)
}

@DeriveExt[Json]
public struct ResponseError {
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
}

public enum ErrorCode <: JsonSerializable & JsonDeserializable<ErrorCode> {
    // Defined by JSON RPC:
    | ParseError
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
            case -32002 => ServerNotInitialized
            case _ => UnknownErrorCode
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
    public func toInteger(): Int64 {
        match (this) {
            case ParseError => -32700
            case ServerNotInitialized => -32002
            case UnknownErrorCode => -32001
        }
    }

    @Frozen
    public func toJson(w: JsonWriter): Unit {
        w.writeValue(toInteger())
    }
}
