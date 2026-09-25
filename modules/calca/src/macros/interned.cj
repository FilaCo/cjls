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

    let visibility = modifiersOf(decl.modifiers)
    let nameLiteral = Token(TokenKind.STRING_LITERAL, stripBackquotes(name.value))
    let superTypes = identitySuperTypes(decl)
    let identity = identityMembers(name)
    let keyStruct = fieldsStruct(key, fields)

    quote(
        $visibility struct $name <: $superTypes {
            private static let CALCA_INGREDIENT = InternedIngredient<$key>($nameLiteral)

            private let calcaId: Id

            $visibility $name(db: Database, $params) {
                calcaId = CALCA_INGREDIENT.intern(db, $key($args))
            }

            $accessors

            $identity

            $kept
        }

        $keyStruct
    )
}
