macro package stdxx.deriving

import std.ast.*

public macro DeriveExt(attrs: Tokens, input: Tokens): Tokens {
    let deriveFns = ArrayList<DeriveFunc>()
    for (attr in attrs) {
        if (attr.kind != TokenKind.IDENTIFIER) {
            continue
        }
        if (let Some(kind) <- DeriveExtKind.nameOf(attr.value)) {
            deriveFns.add(kind.deriveFn)
        }
    }

    if (deriveFns.isEmpty()) {
        return input
    }

    let decl = parseDecl(input)
    var extensions = Tokens()
    for (fn in deriveFns) {
        extensions += fn(decl)
    }

    input + extensions
}

enum DeriveExtKind {
    | JsonSerializable
    | JsonDeserializable
    | Json

    static func nameOf(name: String): ?DeriveExtKind {
        match (name) {
            case "JsonSerializable" => JsonSerializable
            case "JsonDeserializable" => JsonDeserializable
            case "Json" => Json
            case _ => None
        }
    }

    prop deriveFn: DeriveFunc {
        get() {
            match (this) {
                case JsonSerializable => deriveJsonSerializable
                case JsonDeserializable => deriveJsonDeserializable
                case Json => deriveJson
            }
        }
    }
}

type DeriveFunc = (decl: Decl) -> Tokens
