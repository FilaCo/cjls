package jsonrpc

import stdx.serialization.serialization.*
import stdxx.*

public type RequestId = IntegerOrString

public enum Body <: Serializable<Body> {
    | Request(RequestBody)
    | Notification(NotificationBody)
    | Response(ResponseBody)

    /**
     * @throws DataModelException - if DataModel has unexpected type
     * @throws RpcException - if the protocol invariants are not met
     */
    public static func deserialize(dm: DataModel): Body {
        if (let dms: DataModelStruct <- dm) {
            match (dms.get("jsonrpc")) {
                case jsonRpcVersion: DataModelString where jsonRpcVersion.getValue() == "2.0" => ()
                case _ => throw RpcException(ErrorCode.INVALID_REQUEST, "invalid \"jsonrpc\" field value")
            }

            let id = dms.getOrNone("id")

            if (let Some(id) <- id) {
                let result = dms.getOrNone("result")
                let error = dms.getOrNone("error")

                match ((result, error)) {
                    case (Some(_), Some(_)) => throw RpcException(ErrorCode.INVALID_REQUEST, "malformed json")
                    case (Some(result), None) => return ResponseBody(Nullable.deserialize(id), Result(result))
                        .enveloped()
                    case (None, Some(error)) => return ResponseBody(Nullable.deserialize(id),
                        ResultOrError.Error(ResponseError.deserialize(error))).enveloped()
                    case _ => return RequestBody(IntegerOrString.deserialize(id), String.deserialize(dms.get("method")),
                        params: dms.getOrNone("params").map {it => ArrayOrObject.deserialize(it)}).enveloped()
                }
            }

            return NotificationBody(String.deserialize(dms.get("method")),
                params: dms.getOrNone("params").map {it => ArrayOrObject.deserialize(it)}).enveloped()
        }

        throw DataModelException("expected `DataModelStruct`")
    }

    public func serialize(): DataModel {
        let dms = DataModelStruct()
        dms.add(field("jsonrpc", "2.0"))
        match (this) {
            case Request(req) =>
                dms.add(field("id", req.id)).add(field("method", req.method))
                if (let Some(params) <- req.params) {
                    dms.add(field("params", params))
                }
            case Notification(note) =>
                dms.add(field("method", note.method))
                if (let Some(params) <- note.params) {
                    dms.add(field("params", params))
                }
            case Response(resp) =>
                dms.add(field("id", resp.id))
                match (resp.resultOrError) {
                    case Result(dm) => dms.add(Field("result", dm))
                    case Error(err) => dms.add(field("error", err))
                }
        }
        dms
    }

    public func isRequest(): Bool {
        if (let Request(_) <- this) {
            return true
        }

        false
    }

    public func isNotification(): Bool {
        if (let Notification(_) <- this) {
            return true
        }

        false
    }

    public func isResponse(): Bool {
        if (let Response(_) <- this) {
            return true
        }

        false
    }

    /**
     * @throws UnexpectedVariantException - if it is not a `Request`
     */
    public func getRequestBodyOrThrow(): RequestBody {
        if (let Request(reqBody) <- this) {
            return reqBody
        }

        throw UnexpectedVariantException("Request", variantName())
    }

    /**
     * @throws UnexpectedVariantException - if it is not a `Notification`
     */
    public func getNotificationBodyOrThrow(): NotificationBody {
        if (let Notification(noteBody) <- this) {
            return noteBody
        }

        throw UnexpectedVariantException("Notification", variantName())
    }

    /**
     * @throws UnexpectedVariantException - if it is not a `Response`
     */
    public func getResponseBodyOrThrow(): ResponseBody {
        if (let Response(respBody) <- this) {
            return respBody
        }

        throw UnexpectedVariantException("Response", variantName())
    }

    private func variantName(): String {
        match (this) {
            case Request(_) => "Request"
            case Notification(_) => "Notification"
            case Response(_) => "Response"
        }
    }
}

public struct RequestBody {
    public RequestBody(
        public let id: RequestId,
        /**
         * The method to be invoked.
         */
        public let method: String,
        /**
         * The method's params.
         */
        public let params!: ?ArrayOrObject = None
    ) {}

    public func enveloped(): Body {
        Request(this)
    }
}

public struct NotificationBody {
    public NotificationBody(
        /**
         * The method to be invoked.
         */
        public let method: String,
        /**
         * The method's params.
         */
        public let params!: ?ArrayOrObject = None
    ) {}

    public func enveloped(): Body {
        Notification(this)
    }
}

public struct ResponseBody {
    public ResponseBody(
        /**
         * The request id.
         */
        public let id: Nullable<RequestId>, public let resultOrError: ResultOrError) {}

    public static func result<R>(id: Nullable<RequestId>, data: R): ResponseBody where R <: Serializable<R> {
        ResponseBody(id, Result(data.serialize()))
    }

    public static func result(id: Nullable<RequestId>, data: DataModel): ResponseBody {
        ResponseBody(id, Result(data))
    }

    public static func error(id: Nullable<RequestId>, error: ResponseError): ResponseBody {
        ResponseBody(id, ResultOrError.Error(error))
    }

    public func enveloped(): Body {
        Response(this)
    }
}

public enum ResultOrError {
    | Result(DataModel)
    | Error(ResponseError)

    public func isResult(): Bool {
        if (let Result(_) <- this) {
            return true
        }

        false
    }

    public func isError(): Bool {
        !isResult()
    }

    /**
     * @throws UnexpectedVariantException - if it holds an `Error`
     */
    public func getResultOrThrow(): DataModel {
        match (this) {
            case Result(data) => data
            case Error(_) => throw UnexpectedVariantException("Result", "Error")
        }
    }

    /**
     * @throws UnexpectedVariantException - if it holds a `Result`
     */
    public func getErrorOrThrow(): ResponseError {
        match (this) {
            case Error(err) => err
            case Result(_) => throw UnexpectedVariantException("Error", "Result")
        }
    }
}
