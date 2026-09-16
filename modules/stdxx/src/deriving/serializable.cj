macro package stdxx.deriving

import std.ast.*
import std.collection.*

func deriveSerializable(decl: Decl): Tokens {
    if (let enumDecl: EnumDecl <- decl) {
        return deriveSerializableEnum(enumDecl)
    }
    if (bodyDeclsOf(decl).isNone()) {
        return reportUnsupportedDecl(decl)
    }
    let primaryCtor = primaryCtorOf(decl) ?? return reportNoPrimaryCtor(decl)

    let (typeOptions, memberOptions) = collectMarkers()

    let fields = ArrayList<DerivedField>()
    for (param in primaryCtor.funcParams) {
        let options = memberOptions.get(param.identifier.value) ?? MarkerOptions()
        let field = derivedFieldOf(param, options, typeOptions.skipNone) ?? return Tokens()
        fields.add(field)
    }

    if (let Some(clash) <- duplicateWireName(fields)) {
        return report(clash, "two fields share the wire name \"${clash.value}\"", "rename one of them")
    }

    if (typeOptions.transparent) {
        return transparentExtension(decl, typeOptions, fields, memberOptions)
    }

    let typeIdent = decl.identifier
    let typeArgs = typeArgsOf(decl)
    let whereClause = serializableWhereClause(decl)

    var ctorArgs = Tokens()
    var serializeChain = Tokens()
    for ((i, field) in fields.enumerate()) {
        if (i > 0) {
            ctorArgs += Tokens(Token(TokenKind.COMMA))
        }
        ctorArgs += field.toCtorArg()
        serializeChain += field.toSerializeCall()
    }

    quote(
        extend $typeArgs $typeIdent$typeArgs <: Serializable<$typeIdent$typeArgs> $whereClause {
            public static func deserialize(dm: DataModel): $typeIdent$typeArgs {
                let dms = dm.asStructOrThrow()

                $typeIdent$typeArgs($ctorArgs)
            }

            public func serialize(): DataModel {
                DataModelStruct()$serializeChain
            }
        }
    )
}

/**
 * The one field has to be required: its name never reaches the wire, so neither does anything that
 * would tell an absent value from a present one.
 */
private func transparentExtension(
    decl: Decl,
    typeOptions: MarkerOptions,
    fields: ArrayList<DerivedField>,
    memberOptions: HashMap<String, MarkerOptions>
): Tokens {
    let typeIdent = decl.identifier
    if (fields.size != 1) {
        return report(
            typeIdent,
            "`transparent` needs exactly one field",
            "`${typeIdent.value}` declares ${fields.size}"
        )
    }
    if (typeOptions.skipNone || typeOptions.tag.isSome()) {
        return report(
            typeIdent,
            "`transparent` takes no other option on the type",
            "the struct has no object of its own to tag or to omit keys from"
        )
    }

    let field = fields[0]
    if (let Some(options) <- memberOptions.get(field.ident.value)) {
        if (options.rename.isSome() || options.skipNone) {
            return report(
                field.ident,
                "the field of a `transparent` struct takes no options",
                "its name never reaches the wire"
            )
        }
    }
    if (field.shape.isOptional) {
        return report(
            field.ident,
            "the field of a `transparent` struct has to be required",
            "declare it as `${stripBackquotes(field.ident.value)}: T`, not `?T`"
        )
    }

    let typeArgs = typeArgsOf(decl)
    let whereClause = serializableWhereClause(decl)
    let ident = field.ident
    let fieldType = field.fieldType
    let ctorArg = if (field.isNamed) {
        quote($ident: $fieldType.deserialize(dm))
    } else {
        quote($fieldType.deserialize(dm))
    }

    quote(
        extend $typeArgs $typeIdent$typeArgs <: Serializable<$typeIdent$typeArgs> $whereClause {
            public static func deserialize(dm: DataModel): $typeIdent$typeArgs {
                $typeIdent$typeArgs($ctorArg)
            }

            public func serialize(): DataModel {
                this.$ident.serialize()
            }
        }
    )
}

/**
 * How a field's declared type spells the two independent axes - may the key be absent, and may the
 * value be `null`.
 */
enum FieldShape {
    /**
     * `T`, `Nullable<T>` included: the key is always there. A `Nullable<T>` carries its own `null`.
     */
    | Required

    /**
     * `?T`: absent and `null` both read as `None`, the way serde reads an `Option<T>`.
     */
    | Optional

    /**
     * `?Nullable<T>`: absent reads as `None` and `null` as `Some(Null)` - the one shape where the
     * two stay apart.
     */
    | OptionalNullable

    prop isOptional: Bool {
        get() {
            match (this) {
                case Required => false
                case _ => true
            }
        }
    }
}

/**
 * A primary constructor parameter, seen as a field on the wire.
 */
private struct DerivedField {
    DerivedField(
        let ident!: Token,
        let wireName!: Token,
        let isNamed!: Bool,
        let fieldType!: Tokens,
        let shape!: FieldShape,
        let skipNone!: Bool
    ) {}

    /**
     * The argument that reconstructs this field, as it appears in the `deserialize` constructor call.
     */
    func toCtorArg(): Tokens {
        let wireName = this.wireName
        let value = match (shape) {
            case Required => quote(dms.getDeserializedOrThrow($wireName))
            case Optional => quote(dms.getDeserializedOrNoneOnNull($wireName))
            case OptionalNullable => quote(dms.getDeserializedOrNone($wireName))
        }

        if (isNamed) {
            let ident = this.ident
            quote($ident: $value)
        } else {
            value
        }
    }

    /**
     * The link this field adds to the `DataModelStruct` chain in `serialize`.
     *
     * `Option<T>` serializes itself as `null`, so writing the field is the same call whatever its
     * shape - until `skipNone` asks for the key to be dropped instead.
     */
    func toSerializeCall(): Tokens {
        let wireName = this.wireName
        let ident = this.ident

        if (skipNone && shape.isOptional) {
            quote(.addFieldIfSome($wireName, this.$ident))
        } else {
            quote(.add(field($wireName, this.$ident)))
        }
    }
}

private func derivedFieldOf(param: FuncParam, options: MarkerOptions, skipNoneOnType: Bool): ?DerivedField {
    let tokens = param.toTokens()
    if (!isMemberParam(tokens)) {
        diagReport(
            DiagReportLevel.ERROR,
            tokens,
            "`@DeriveExt[Serializable]` needs every primary constructor parameter to declare a field",
            "prefix it with `let`, or hand-write `Serializable`"
        )
        return None
    }

    let ident = param.identifier
    let wireName = options.rename ?? stripBackquotes(ident.value)

    DerivedField(
        ident: ident,
        wireName: Token(TokenKind.STRING_LITERAL, wireName),
        isNamed: isNamedParam(tokens),
        fieldType: param.paramType.toTokens(),
        shape: shapeOf(param.paramType),
        skipNone: skipNoneOnType || options.skipNone
    )
}

/**
 * `let x: T` / `var x: T` declares a field, a bare `x: T` is a constructor argument that is gone
 * once the constructor returns - nothing to serialize, and nothing to reconstruct it from.
 */
private func isMemberParam(tokens: Tokens): Bool {
    let head = headTokenOf(tokens) ?? return false

    head.kind == TokenKind.LET || head.kind == TokenKind.VAR
}

private func isNamedParam(tokens: Tokens): Bool {
    for (token in tokens) {
        if (token.kind == TokenKind.NOT) {
            return true
        }
        if (token.kind == TokenKind.COLON) {
            return false
        }
    }

    false
}

func shapeOf(paramType: TypeNode): FieldShape {
    let tokens = paramType.toTokens()
    if (tokens.size == 0) {
        return Required
    }

    let head = tokens[0]
    if (head.kind == TokenKind.QUEST) {
        return optionalShapeOf(tokens, 1)
    }
    if (head.kind == TokenKind.IDENTIFIER && head.value == "Option") {
        return optionalShapeOf(tokens, 2)
    }

    Required
}

/**
 * `Nullable<T>` under the option is the only inner type that changes what an absent key means, so
 * it is the only one worth looking at.
 *
 * The name is matched against the source, and nothing more is knowable at expansion time: a field
 * declared through an alias of it (`import stdxx.Nullable as MaybeNull`, `?MaybeNull<T>`) reads as
 * a plain optional, and an explicit `null` then collapses to `None` instead of `Some(Null)`.
 * Spell `Nullable` outright wherever the distinction matters.
 */
private func optionalShapeOf(tokens: Tokens, innerAt: Int64): FieldShape {
    if (innerAt < tokens.size && tokens[innerAt].value == "Nullable") {
        OptionalNullable
    } else {
        Optional
    }
}

/**
 * Every type parameter has to be serializable for the extension to be, so its own bounds get
 * `Serializable<T>` appended.
 */
func serializableWhereClause(decl: Decl): Tokens {
    if (!decl.isGenericDecl) {
        return Tokens()
    }

    let clauses = ArrayList<String>()
    for (typeParam in decl.genericParam.parameters) {
        let bounds = ArrayList<String>()
        for (constraint in decl.genericConstraint) {
            if (constraint.typeArgument.toTokens().toString() != typeParam.value) {
                continue
            }
            for (bound in constraint.upperBounds) {
                bounds.add(bound.toTokens().toString())
            }
        }
        bounds.add("Serializable<${typeParam.value}>")

        clauses.add("${typeParam.value} <: ${joined(bounds, " & ")}")
    }

    cangjieLex("where ${joined(clauses, ", ")}")
}

/**
 * The identifier of the first field whose name on the wire was already taken - two of them would
 * write the same key, and both would read whichever value came last.
 */
private func duplicateWireName(fields: ArrayList<DerivedField>): ?Token {
    let taken = HashSet<String>()
    for (field in fields) {
        if (!taken.add(field.wireName.value)) {
            return field.ident
        }
    }

    None
}

private func report(ident: Token, message: String, hint: String): Tokens {
    diagReport(DiagReportLevel.ERROR, ident.toTokens(), message, hint)

    Tokens()
}

private func reportUnsupportedDecl(decl: Decl): Tokens {
    diagReport(
        DiagReportLevel.ERROR,
        decl.identifier.toTokens(),
        "`@DeriveExt[Serializable]` only derives for a `struct`, a `class` or an `enum`",
        "hand-write `Serializable` for anything else"
    )

    Tokens()
}

private func reportNoPrimaryCtor(decl: Decl): Tokens {
    diagReport(
        DiagReportLevel.ERROR,
        decl.identifier.toTokens(),
        "`@DeriveExt[Serializable]` needs a primary constructor to read the fields from",
        "declare the fields as primary constructor parameters, or hand-write `Serializable`"
    )

    Tokens()
}
