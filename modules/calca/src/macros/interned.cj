macro package calca.macros

import std.ast.*
import std.collection.*

/**
 * Makes a struct interned in the database, as salsa's `#[salsa::interned]` is: equal fields give
 * the one value, which is only an `Id`, so comparing and hashing it costs no more than an integer's.
 *
 * ```cangjie
 * @CalcaInterned
 * public struct Name {
 *     public let text: String
 * }
 * // gives
 * public Name(db: Database, text: String)   // Name(db, "x") == Name(db, "x")
 * public func text(db: Database): String
 * ```
 *
 * Fields are `let`, and `Hashable` and `Equatable`: together they are the value's identity. Member
 * functions are kept as they are.
 *
 * A value interned by queries that read only `Low` inputs is collected once it goes unused for 3
 * active revisions (revisions the type was used in at all), and the memos keyed by it with it; its
 * `Id` is then stale, and reading it throws. `@CalcaInterned[revisions: N]` says how many;
 * `@CalcaInterned[forever]` keeps every value as long as the database, and records no dependency
 * on interning.
 */
public macro CalcaInterned(input: Tokens): Tokens {
    interned(input, quote())
}

public macro CalcaInterned(attrs: Tokens, input: Tokens): Tokens {
    let revisions = match (attrs.size) {
        case 1 where attrs[0].value == "forever" => quote(, revisions: Option<Int64>.None)
        // a literal has no sign, `-` is a token of its own
        case 3 where attrs[0].value == "revisions" && attrs[1].kind == TokenKind.COLON && attrs[2].kind ==
            TokenKind.INTEGER_LITERAL && attrs[2].value != "0" =>
            let count = attrs[2]
            quote(, revisions: Option<Int64>.Some($count))
        case _ where attrs.size > 0 && attrs[0].value == "revisions" =>
            diagReport(DiagReportLevel.ERROR, attrs,
                "`revisions` takes how many active revisions a value may go unused, at least 1: `revisions: 3`",
                "to keep every value, `@CalcaInterned[forever]`")
            return input
        case _ =>
            diagReport(DiagReportLevel.ERROR, attrs, "`@CalcaInterned` takes `revisions: N` or `forever`", "")
            return input
    }
    interned(input, revisions)
}

private func interned(input: Tokens, revisions: Tokens): Tokens {
    let decl = plainStruct(input, "CalcaInterned") ?? return input
    let (fields, kept) = storedFields(decl, "CalcaInterned") ?? return input
    for (field in fields where field.keyword.kind == TokenKind.VAR) {
        diagReport(DiagReportLevel.ERROR, field.toTokens(), "an interned value never changes: its fields are `let`",
            "for a value that changes, use `@CalcaInput`")
        return input
    }

    let name = decl.identifier
    let key = Token(TokenKind.IDENTIFIER, "CalcaFields_" + stripBackquotes(name.value))
    var params = Tokens()
    var args = Tokens()
    var accessors = Tokens()
    for (field in fields) {
        let ident = field.identifier
        let fieldType = field.declType.toTokens()
        let visibility = modifiersOf(field.modifiers)
        params += quote($ident: $fieldType, )
        args += quote($ident, )
        accessors += quote(
            $visibility func $ident(db: Database): $fieldType {
                CALCA_INGREDIENT.lookup(db, calcaId).$ident
            }
        )
    }
    accessors += quote(
        public func calcaKey(): DatabaseKey {
            CALCA_INGREDIENT.key(calcaId)
        }
    )

    let ingredient = quote(InternedIngredient<$key>($(nameLiteral(name)) $revisions))
    let create = quote(CALCA_INGREDIENT.intern(db, $key($args)))
    identityStruct(decl, ingredient, params, create, accessors, kept, identity: quote(& InternedValue)) +
        fieldsStruct(key, fields)
}
