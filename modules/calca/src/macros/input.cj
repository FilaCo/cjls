macro package calca.macros

import std.ast.*
import std.collection.*

/**
 * Makes a struct an input of the database: what it declares as fields lives in the database, and a
 * value of it is only the row's `Id`, as salsa's `#[salsa::input]` is.
 *
 * ```cangjie
 * @CalcaInput
 * public struct SourceFile {
 *     public let path: String
 *     public var text: String
 * }
 * // gives
 * public SourceFile(db: Database, path: String, text: String, durability!: Durability = Durability.Low)
 * public func path(db: Database): String
 * public func text(db: Database): String
 * public func setText(db: Database): Setter<String>   // file.setText(db).to(text)
 * ```
 *
 * Every field gets a getter, recorded as read by the query that calls it; a `var` one also gets a
 * setter, which starts a new revision. Fields take the visibility they are declared with, and have
 * no initializer. Member functions are kept as they are. The type is `Hashable` and `Equatable` by
 * its `Id`.
 */
public macro CalcaInput(input: Tokens): Tokens {
    let decl = plainStruct(input, "CalcaInput") ?? return input
    let (fields, kept) = storedFields(decl, "CalcaInput") ?? return input

    let name = decl.identifier
    var fieldNames = Tokens()
    var params = Tokens()
    var puts = Tokens()
    var accessors = Tokens()
    for (i in 0..fields.size) {
        let field = fields[i]
        let ident = field.identifier
        let fieldType = field.declType.toTokens()
        let visibility = modifiersOf(field.modifiers)
        let index = Token(TokenKind.INTEGER_LITERAL, "${i}")
        fieldNames += Token(TokenKind.STRING_LITERAL, stripBackquotes(ident.value))
        fieldNames += Token(TokenKind.COMMA)
        params += quote($ident: $fieldType, )
        puts += quote(row.put<$fieldType>($index, $ident)
        )
        accessors += quote(
            $visibility func $ident(db: Database): $fieldType {
                CALCA_INGREDIENT.get<$fieldType>(db, $index, calcaId)
            }
        )
        if (field.keyword.kind == TokenKind.VAR) {
            let setter = Token(TokenKind.IDENTIFIER, "set" + capitalized(stripBackquotes(ident.value)))
            accessors += quote(
                $visibility func $setter(db: Database): Setter<$fieldType> {
                    CALCA_INGREDIENT.set<$fieldType>(db, $index, calcaId)
                }
            )
        }
    }

    let visibility = modifiersOf(decl.modifiers)
    let nameLiteral = Token(TokenKind.STRING_LITERAL, stripBackquotes(name.value))
    let superTypes = identitySuperTypes(decl)
    let identity = identityMembers(name)

    quote(
        $visibility struct $name <: $superTypes {
            private static let CALCA_INGREDIENT = InputIngredient($nameLiteral, [$fieldNames])

            private let calcaId: Id

            $visibility $name(db: Database, $params durability!: Durability = Durability.Low) {
                calcaId = CALCA_INGREDIENT.create(db, durability) {
                    row => $puts
                }
            }

            $accessors

            $identity

            $kept
        }
    )
}
