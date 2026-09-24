macro package calca.macros

import std.ast.*
import std.collection.*

func modifiersOf(modifiers: ArrayList<Modifier>): Tokens {
    var tokens = Tokens()
    for (modifier in modifiers) {
        tokens += modifier.toTokens()
    }
    tokens
}

/**
 * `` `type` `` -> `type`: backquotes escape an identifier in the source and are no part of its name.
 */
func stripBackquotes(ident: String): String {
    if (ident.size >= 2 && ident.startsWith("`") && ident.endsWith("`")) {
        ident[1..ident.size - 1]
    } else {
        ident
    }
}

func capitalized(name: String): String {
    if (name.isEmpty()) {
        name
    } else {
        name[0..1].toAsciiUpper() + name[1..]
    }
}

/**
 * The struct `input` declares, reporting anything else, or a generic one.
 */
func plainStruct(input: Tokens, macroName: String): ?StructDecl {
    match (parseDecl(input)) {
        case sd: StructDecl where sd.isGenericDecl =>
            diagReport(DiagReportLevel.ERROR, input, "a `@${macroName}` type is not generic", "")
            None
        case sd: StructDecl => sd
        case _ =>
            diagReport(DiagReportLevel.ERROR, input, "`@${macroName}` goes on a struct", "")
            None
    }
}

/**
 * The fields of a type whose fields live in the database, and the rest of its members, kept as they
 * are. `None` once a field that cannot be one was reported.
 */
func storedFields(decl: StructDecl, macroName: String): ?(ArrayList<VarDecl>, Tokens) {
    let fields = ArrayList<VarDecl>()
    var kept = Tokens()
    for (member in decl.body.decls) {
        match (member) {
            case field: VarDecl =>
                if (!isFieldValid(field, macroName)) {
                    return None
                }
                fields.add(field)
            case _ => kept += member.toTokens()
        }
    }
    (fields, kept)
}

private func isFieldValid(field: VarDecl, macroName: String): Bool {
    let hasInitializer = try {
        field.expr
        true
    } catch (_: ASTException) {
        false
    }
    if (hasInitializer) {
        diagReport(DiagReportLevel.ERROR, field.toTokens(), "a `@${macroName}` field has no initializer",
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
        diagReport(DiagReportLevel.ERROR, field.toTokens(), "a `@${macroName}` field declares its type", "")
        return false
    }
    for (modifier in field.modifiers where modifier.keyword.kind == TokenKind.STATIC) {
        diagReport(DiagReportLevel.ERROR, field.toTokens(), "a `@${macroName}` type has no static fields", "")
        return false
    }
    true
}

/**
 * The supertypes of a type that is its `calcaId`: its identity ones, then those the user wrote.
 */
func identitySuperTypes(decl: StructDecl): Tokens {
    let name = decl.identifier
    var superTypes = quote(Hashable & Equatable<$name> & ToString)
    for (superType in decl.superTypes) {
        superTypes += quote(& $(superType.toTokens()))
    }
    superTypes
}

/**
 * `hashCode`, `==`, `!=` and `toString` of a type that is its `calcaId`, described by its
 * `CALCA_INGREDIENT`.
 */
func identityMembers(name: Token): Tokens {
    quote(
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
    )
}

/**
 * A struct of `fields`, `Hashable` and `Equatable` by all of them: several values as one key, which
 * a tuple cannot be.
 */
func fieldsStruct(name: Token, fields: ArrayList<VarDecl>): Tokens {
    var params = Tokens()
    var hashes = Tokens()
    var equal = quote(true)
    for (field in fields) {
        let ident = field.identifier
        let fieldType = field.declType.toTokens()
        params += quote(let $ident: $fieldType, )
        hashes += quote(hasher.write($ident.hashCode())
        )
        equal += quote(&& $ident == other.$ident)
    }
    quote(
        struct $name <: Hashable & Equatable<$name> {
            $name($params) {}

            public func hashCode(): Int64 {
                var hasher = DefaultHasher()
                $hashes
                hasher.finish()
            }

            public operator func ==(other: $name): Bool {
                $equal
            }

            public operator func !=(other: $name): Bool {
                !(this == other)
            }
        }
    )
}
