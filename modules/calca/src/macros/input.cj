macro package calca.macros

import std.ast.*
import std.collection.*

/**
 * Makes a struct an input of the database: what it declares as fields lives in the database, and a
 * value of it is only the row's `Id`, as salsa's `#[salsa::input]` is.
 *
 * ```cangjie
 * @Input
 * public struct SourceFile {
 *     public let path: String
 *     public var text: String
 * }
 * // gives
 * public init(db: Database, path: String, text: String, durability!: Durability = Durability.Low)
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
public macro Input(input: Tokens): Tokens {
    let decl = match (parseDecl(input)) {
        case sd: StructDecl => sd
        case _ =>
            diagReport(DiagReportLevel.ERROR, input, "`@Input` goes on a struct", "")
            return input
    }
    if (decl.isGenericDecl) {
        diagReport(DiagReportLevel.ERROR, input, "an input is not generic", "")
        return input
    }

    let name = decl.identifier
    let fields = ArrayList<VarDecl>()
    var kept = Tokens()
    for (member in decl.body.decls) {
        match (member) {
            case field: VarDecl =>
                if (!isFieldValid(field)) {
                    return input
                }
                fields.add(field)
            case _ => kept += member.toTokens()
        }
    }

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
    var superTypes = quote(Hashable & Equatable<$name> & ToString)
    for (superType in decl.superTypes) {
        superTypes += quote(& $(superType.toTokens()))
    }

    quote(
        $visibility struct $name <: $superTypes {
            private static let CALCA_INGREDIENT = InputIngredient($nameLiteral, [$fieldNames])

            private let calcaId: Id

            $visibility init(db: Database, $params durability!: Durability = Durability.Low) {
                calcaId = CALCA_INGREDIENT.create(db, durability) {
                    row => $puts
                }
            }

            $accessors

            public func hashCode(): Int64 {
                calcaId.hashCode()
            }

            public operator func ==(other: $name): Bool {
                calcaId == other.calcaId
            }

            public operator func !=(other: $name): Bool {
                calcaId != other.calcaId
            }

            public func toString(): String {
                CALCA_INGREDIENT.describe(calcaId)
            }

            $kept
        }
    )
}

private func isFieldValid(field: VarDecl): Bool {
    let hasInitializer = try {
        field.expr
        true
    } catch (_: ASTException) {
        false
    }
    if (hasInitializer) {
        diagReport(DiagReportLevel.ERROR, field.toTokens(), "an input field has no initializer",
            "its value is given to the constructor")
        return false
    }
    let hasType = try {
        field.declType
        true
    } catch (_: ASTException) {
        false
    }
    if (!hasType) {
        diagReport(DiagReportLevel.ERROR, field.toTokens(), "an input field declares its type", "")
        return false
    }
    for (modifier in field.modifiers where modifier.keyword.kind == TokenKind.STATIC) {
        diagReport(DiagReportLevel.ERROR, field.toTokens(), "an input has no static fields", "")
        return false
    }
    true
}
