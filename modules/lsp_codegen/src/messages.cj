package lsp_codegen

import std.collection.ArrayList

/**
 * LSP's `void`: the params of `exit`, the result of `shutdown`.
 */
const UNIT_TYPE = "Unit"

/**
 * The struct is the spec of the message, not the message itself.
 */
const SPEC_SUFFIX = "Spec"

struct MessageIr {
    MessageIr(
        let doc: DocIr,
        let ident!: String,
        let method!: String,
        let direction!: MessageDirection,
        /**
         * `None` for a message that takes none - `exit`.
         */
        let params!: ?TypeIr = None,
        /**
         * `None` for a request answered with a bare `null` - `shutdown` - and for a notification.
         */
        let result!: ?TypeIr = None,
        let isRequest!: Bool
    ) {}

    prop paramsType: String {
        get() {
            params?.toString() ?? UNIT_TYPE
        }
    }

    prop resultType: String {
        get() {
            result?.toString() ?? UNIT_TYPE
        }
    }
}

/**
 * Runs before the declarations are collected: it meets unions and literals only messages use.
 */
func resolveMessages(resolver: TypeResolver, mm: MetaModel): Array<MessageIr> {
    let messages = ArrayList<MessageIr>()
    for (request in mm.requests) {
        let owner = messageIdentOf(request.typeName, request.method)
        // not declared yet, but resolved all the same: the types they name must exist
        resolveUnused(resolver, owner, [("PartialResult", request.partialResult), ("ErrorData", request.errorData),
            ("RegistrationOptions", request.registrationOptions)])
        messages.add(
            MessageIr(
                resolveDoc(request),
                ident: owner + SPEC_SUFFIX,
                method: request.method,
                direction: request.messageDirection,
                params: paramsOf(resolver, owner, request.params),
                result: resultOf(resolver, owner, request.result),
                isRequest: true
            )
        )
    }
    for (notification in mm.notifications) {
        let owner = messageIdentOf(notification.typeName, notification.method)
        resolveUnused(resolver, owner, [("RegistrationOptions", notification.registrationOptions)])
        messages.add(
            MessageIr(
                resolveDoc(notification),
                ident: owner + SPEC_SUFFIX,
                method: notification.method,
                direction: notification.messageDirection,
                params: paramsOf(resolver, owner, notification.params),
                isRequest: false
            )
        )
    }

    messages.toArray()
}

/**
 * A name made up from the method could clash with a type, so a message without `typeName` is refused.
 */
private func messageIdentOf(typeName: ?String, method: String): String {
    typeName.getOrThrow {=> IllegalStateException("message `${method}` has no type name")}
}

private func paramsOf(resolver: TypeResolver, owner: String, params: ?OneOrMany<Type>): ?TypeIr {
    match (params) {
        case None => None
        case Some(One(t)) => resolver.resolve(t, context: owner + "Params")
        // positional params: LSP 3.x declares none, and a struct is no fit for them
        case Some(Many(_)) => throw IllegalStateException("`${owner}` takes its params by position")
    }
}

private func resultOf(resolver: TypeResolver, owner: String, result: Type): ?TypeIr {
    match (result) {
        case Base(Null) => None
        case _ => resolver.resolve(result, context: owner + "Result")
    }
}

private func resolveUnused(resolver: TypeResolver, owner: String, types: Array<(String, ?Type)>): Unit {
    for ((part, t) in types) {
        match (t) {
            case Some(Base(Null)) | None => ()
            case Some(some) => resolver.resolve(some, context: owner + part)
        }
    }
}

extend CjEmitter {
    func emitMessage(messageIr: MessageIr): Unit {
        let ident = escapedIdent(messageIr.ident).value
        let types = if (messageIr.isRequest) {
            "Request<${messageIr.paramsType}, ${messageIr.resultType}>"
        } else {
            "Notification<${messageIr.paramsType}>"
        }
        // the direction is in the type, so a handler of a message the server sends does not compile
        let (spec, isInbound) = match (messageIr.direction) {
            case ClientToServer => ("LspInbound${types}", true)
            case ServerToClient => ("LspOutbound${types}", false)
            case Both => ("LspInbound${types} & LspOutbound${types}", true)
        }
        let direction = match (messageIr.direction) {
            case ClientToServer => "ClientToServer"
            case ServerToClient => "ServerToClient"
            case Both => "Both"
        }

        emitDoc(messageIr.doc)
        // verbatim: cjfmt leaves the spaces `Tokens` puts around `<` and `>` in a type
        emitln("public struct ${ident} <: ${spec} {")
        indented {
            =>
                emitln("public static prop METHOD: String {")
                indented {=> emitln("get() { \"${messageIr.method}\" }")}
                emitln("}")
                nl()
                emitln("public static prop DIRECTION: MessageDirection {")
                indented {=> emitln("get() { MessageDirection.${direction} }")}
                emitln("}")
                nl()
                emitln("public init() {}")
                nl()
                emitln("public prop method: String {")
                indented {=> emitln("get() { METHOD }")}
                emitln("}")
                if (isInbound) {
                    nl()
                    emitCodec(messageIr)
                }
        }
        emitln("}")
    }

    /**
     * Written out per message rather than inherited: only here is it known whether there are params
     * to decode and a result to encode, and `Unit` - which stands for neither - can never be
     * `Serializable`, being a type of `std`.
     */
    private func emitCodec(messageIr: MessageIr): Unit {
        emitln("public func decodeParams(params: ?ArrayOrObject): ${messageIr.paramsType} {")
        indented {
            => match (messageIr.params) {
                case Some(params) => emitln("decodeMessageParams<${params}>(params)")
                case None => emitln("()")
            }
        }
        emitln("}")
        if (!messageIr.isRequest) {
            return
        }

        nl()
        emitln("public func encodeResult(result: ${messageIr.resultType}): DataModel {")
        indented {
            => match (messageIr.result) {
                case Some(_) => emitln("result.serialize()")
                case None => emitln("DataModelNull()")
            }
        }
        emitln("}")
    }
}
