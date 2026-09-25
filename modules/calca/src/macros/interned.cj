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
 * Fields are `let`, and `Hashable` and `Equatable`: together they are the value's identity. An
 * interned value lives as long as its database, so reading it records no dependency. Member
 * functions are kept as they are.
 */
public macro CalcaInterned(input: Tokens): Tokens {
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

    let ingredient = quote(InternedIngredient<$key>($(nameLiteral(name))))
    let create = quote(CALCA_INGREDIENT.intern(db, $key($args)))
    identityStruct(decl, ingredient, params, create, accessors, kept) + fieldsStruct(key, fields)
}
