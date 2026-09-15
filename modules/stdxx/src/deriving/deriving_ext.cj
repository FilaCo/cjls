macro package stdxx.deriving

import std.ast.*
import std.collection.*

const DERIVE_EXT_MACRO = "DeriveExt"

/**
 * Generates the interface implementations named in the attributes as extensions of the annotated
 * declaration
 * ```cangjie
 * @DeriveExt[Serializable]
 * struct Position {
 *     Position(let line!: UInt32, let character!: UInt32) {}
 * }
 * ```
 */
public macro DeriveExt(attrs: Tokens, input: Tokens): Tokens {
    let deriveFns = ArrayList<DeriveFunc>()
    for (attr in attrs) {
        if (attr.kind != TokenKind.IDENTIFIER) {
            continue
        }
        match (DeriveExtKind.nameOf(attr.value)) {
            case Some(kind) => deriveFns.add(kind.deriveFn)
            case None => diagReport(
                DiagReportLevel.ERROR,
                Tokens(attr),
                "`@DeriveExt` cannot derive `${attr.value}`",
                "it knows: ${DeriveExtKind.known()}"
            )
        }
    }

    if (deriveFns.isEmpty()) {
        return input
    }

    let decl = parseDecl(input)

    var extensions = Tokens()
    for (deriveFn in deriveFns) {
        extensions += deriveFn(decl)
    }

    input + extensions
}

enum DeriveExtKind {
    | Serializable

    static func nameOf(name: String): ?DeriveExtKind {
        match (name) {
            case "Serializable" => Serializable
            case _ => None
        }
    }

    static func known(): String {
        "Serializable"
    }

    prop deriveFn: DeriveFunc {
        get() {
            match (this) {
                case Serializable => deriveSerializable
            }
        }
    }
}

type DeriveFunc = (decl: Decl) -> Tokens
