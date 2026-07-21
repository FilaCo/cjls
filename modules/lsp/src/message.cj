package lsp

import stdx.encoding.json.stream.*

public type RequestId = IntegerOrString

public enum Message <: JsonSerializable & JsonDeserializable<Message> {
    | Request(RequestMessage)
    | Notification(NotificationMessage)
    | Response(ResponseMessage)

    @Frozen
    public static func fromJson(r: JsonReader): Message {
        // r.peek().map { tok => }.getOrThrow()

        throw Exception()
    }

    @Frozen
    public func toJson(w: JsonWriter): Unit {
        match (this) {
            case Request(req) => w.writeValue(req)
            case Notification(n) => w.writeValue(n)
            case Response(res) => w.writeValue(res)
        }
    }
}

public struct RequestMessage <: JsonSerializable & JsonDeserializable<RequestMessage> {
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
    public static func fromJson(r: JsonReader): RequestMessage {
        throw Exception()
    }

    @Frozen
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeJsonRpcField()
        w.writeName("id").writeValue(id).writeName("method").writeValue(method)

        if (let Some(p) <- params) {
            w.writeName("params").writeValue(p)
        }

        w.endObject()
    }
}

public struct NotificationMessage <: JsonSerializable & JsonDeserializable<NotificationMessage> {
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
    public static func fromJson(r: JsonReader): NotificationMessage {
        throw Exception()
    }

    @Frozen
    public func toJson(w: JsonWriter): Unit {}
}

public struct ResponseMessage <: JsonSerializable & JsonDeserializable<ResponseMessage> {
    @Frozen
    public ResponseMessage(public let id: ?RequestId) {}

    @Frozen
    public static func fromJson(r: JsonReader): ResponseMessage {
        throw Exception()
    }

    @Frozen
    public func toJson(w: JsonWriter): Unit {}
}

public struct ResponseError <: JsonSerializable & JsonDeserializable<ResponseMessage> {
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
    public static func fromJson(r: JsonReader): ResponseMessage {
        throw Exception()
    }

    @Frozen
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("code").writeValue(code).writeName("message").writeValue(message)
        if (let Some(d) <- data) {
            w.writeName("data").writeValue(d)
        }
        w.endObject()
    }
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
        r.peek().map {
            tok =>
                if (tok == JsonNumber) {
                    return fromInteger(r.readValue<Int64>()) // TODO: custom exception
                }
                throw Exception() // TODO: custom exception
        }.getOrThrow() // TODO: custom exception
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
