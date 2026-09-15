macro package stdxx.deriving

import std.ast.*
import std.collection.*

func deriveSerializableEnum(decl: EnumDecl): Tokens {
    let (typeOptions, variantOptions) = collectMarkers()

    let variants = ArrayList<DerivedVariant>()
    for (ctor in decl.constructors) {
        let ident = ctor.identifier
        let options = variantOptions.get(ident.value) ?? MarkerOptions()
        let payloadTypes = ArrayList<Tokens>()
        let payloadShapes = ArrayList<FieldShape>()
        for (payloadType in ctor.typeArguments) {
            payloadTypes.add(payloadType.toTokens())
            payloadShapes.add(shapeOf(payloadType))
        }

        variants.add(
            DerivedVariant(
                ident: ident,
                value: options.value ?? WireValue.ofString(stripBackquotes(ident.value)),
                payloadTypes: payloadTypes.toArray(),
                payloadShapes: payloadShapes.toArray(),
                payloadNames: options.payload
            )
        )
    }

    if (variants.isEmpty()) {
        return report(decl, "`@DeriveExt[Serializable]` needs at least one variant", "there is nothing to serialize")
    }

    if (let Some(clash) <- duplicateWireValue(variants)) {
        return report(clash, "two variants share the same value on the wire", "give one of them a different `value:`")
    }

    match (typeOptions.tag) {
        case Some(tag) => taggedEnumExtension(decl, variants, tag, typeOptions.skipNone)
        case None =>
            if (isScalar(variants)) {
                scalarEnumExtension(decl, variants)
            } else {
                untaggedEnumExtension(decl, variants)
            }
    }
}

/**
 * A variant of an enum, seen as one alternative on the wire.
 */
private struct DerivedVariant {
    DerivedVariant(
        let ident!: Token,
        let value!: WireValue,
        let payloadTypes!: Array<Tokens>,
        let payloadShapes!: Array<FieldShape>,
        let payloadNames!: Array<String>
    ) {}

    /**
     * `p0, p1, ...` - the names the generated `match` binds this variant's payload to.
     */
    func payloadBindings(): Array<Token> {
        let bindings = ArrayList<Token>()
        for (i in 0..payloadTypes.size) {
            bindings.add(Token(TokenKind.IDENTIFIER, "p${i}"))
        }

        bindings.toArray()
    }
}

private func isScalar(variants: ArrayList<DerivedVariant>): Bool {
    for (variant in variants) {
        if (variant.payloadTypes.size > 0) {
            return false
        }
    }

    true
}

/**
 * Variants without a payload are the value itself - a string, or an integer when `value:` says so.
 */
private func scalarEnumExtension(decl: EnumDecl, variants: ArrayList<DerivedVariant>): Tokens {
    let isInteger = variants[0].value.isInteger
    for (variant in variants) {
        if (variant.value.isInteger != isInteger) {
            return report(
                decl,
                "`@DeriveExt[Serializable]` needs every `value:` of an enum to be of one kind",
                "`${variant.ident.value}` breaks the string/integer choice the other variants made"
            )
        }
    }

    let reader = if (isInteger) {
        quote(dm.asIntOrThrow())
    } else {
        quote(dm.asStringOrThrow())
    }
    let dataModel = if (isInteger) {
        quote(DataModelInt)
    } else {
        quote(DataModelString)
    }

    var readCases = Tokens()
    var writeCases = Tokens()
    for (variant in variants) {
        let ident = variant.ident
        let literal = variant.value.literal
        readCases += quote(
            case $literal => $ident
        )
        writeCases += quote(
            case $ident => $dataModel($literal)
        )
    }
    let unexpected = Token(TokenKind.STRING_LITERAL, "unexpected `${decl.identifier.value}` value: ")

    enumExtension(
        decl,
        quote(
            match ($reader) {
                $readCases
                case value => throw DataModelException($unexpected + value.toString())
            }
        ),
        quote(
            match (this) {
                $writeCases
            }
        )
    )
}

/**
 * No discriminator anywhere: the variant is whichever one the value can be read as, tried in
 * declaration order. The same rule - and the same caveat about an earlier variant shadowing a later
 * one - as `#[serde(untagged)]`.
 *
 * Any exception means "not this variant", not just a `DataModelException`: reading an `Int32` out
 * of a value too large for it throws `OverflowException`, and a narrower variant failing that way
 * is exactly what the next one is for.
 */
private func untaggedEnumExtension(decl: EnumDecl, variants: ArrayList<DerivedVariant>): Tokens {
    var attempts = Tokens()
    var writeCases = Tokens()
    for (variant in variants) {
        if (variant.payloadTypes.size != 1) {
            return report(
                decl,
                "an untagged `@DeriveExt[Serializable]` enum needs exactly one payload per variant",
                "`${variant.ident.value}` carries ${variant.payloadTypes.size} - add `@DeriveExtSerializable[tag: \"...\"]` to make it tagged"
            )
        }

        let ident = variant.ident
        let payloadType = variant.payloadTypes[0]
        attempts += quote(
            try {
                return $ident($payloadType.deserialize(dm))
            } catch (_: Exception) {}
        )
        writeCases += quote(
            case $ident(payload) => payload.serialize()
        )
    }
    let unexpected = Token(TokenKind.STRING_LITERAL, "no `${decl.identifier.value}` variant matched the value")

    enumExtension(
        decl,
        quote(
            $attempts
            throw DataModelException($unexpected)
        ),
        quote(
            match (this) {
                $writeCases
            }
        )
    )
}

/**
 * The discriminator travels in a field of the object, next to the payload.
 */
private func taggedEnumExtension(
    decl: EnumDecl,
    variants: ArrayList<DerivedVariant>,
    tag: String,
    skipNone: Bool
): Tokens {
    let tagLiteral = Token(TokenKind.STRING_LITERAL, tag)

    var readCases = Tokens()
    var writeCases = Tokens()
    for (variant in variants) {
        if (variant.value.isInteger) {
            return report(
                decl,
                "a tagged `@DeriveExt[Serializable]` enum needs a string `value:` on every variant",
                "`${variant.ident.value}` asks for an integer, and the tag field holds a string"
            )
        }
        if (variant.payloadNames.size != variant.payloadTypes.size) {
            return report(
                decl,
                "a tagged `@DeriveExt[Serializable]` enum needs `payload:` to name every payload of a variant",
                "`${variant.ident.value}` carries ${variant.payloadTypes.size} of them, `payload:` names ${variant.payloadNames.size}"
            )
        }

        let ident = variant.ident
        let literal = variant.value.literal
        let bindings = variant.payloadBindings()

        var readArgs = Tokens()
        var writeFields = Tokens()
        for ((i, name) in variant.payloadNames |> enumerate) {
            let nameLiteral = Token(TokenKind.STRING_LITERAL, name)
            let binding = bindings[i]
            let shape = variant.payloadShapes[i]
            if (i > 0) {
                readArgs += Tokens(Token(TokenKind.COMMA))
            }
            readArgs += match (shape) {
                case Required => quote(dms.getDeserializedOrThrow($nameLiteral))
                case Optional => quote(dms.getDeserializedOrNoneOnNull($nameLiteral))
                case OptionalNullable => quote(dms.getDeserializedOrNone($nameLiteral))
            }
            writeFields += if (skipNone && shape.isOptional) {
                quote(.addFieldIfSome($nameLiteral, $binding))
            } else {
                quote(.add(field($nameLiteral, $binding)))
            }
        }

        readCases += if (bindings.size == 0) {
            quote(
                case $literal => $ident
            )
        } else {
            quote(
                case $literal => $ident($readArgs)
            )
        }
        writeCases += if (bindings.size == 0) {
            quote(
                case $ident => DataModelStruct().add(field($tagLiteral, $literal))
            )
        } else {
            let pattern = joinedTokens(bindings)
            quote(
                case $ident($pattern) => DataModelStruct().add(field($tagLiteral, $literal))$writeFields
            )
        }
    }
    let unexpected = Token(TokenKind.STRING_LITERAL, "unexpected `${decl.identifier.value}` ${tag}: ")

    enumExtension(
        decl,
        quote(
            let dms = dm.asStructOrThrow()

            match (dms.getDeserializedOrThrow<String>($tagLiteral)) {
                $readCases
                case tag => throw DataModelException($unexpected + tag)
            }
        ),
        quote(
            match (this) {
                $writeCases
            }
        )
    )
}

/**
 * The identifier of the first variant whose value on the wire was already taken - two of them would
 * be indistinguishable, and the earlier one would answer for both.
 */
private func duplicateWireValue(variants: ArrayList<DerivedVariant>): ?Token {
    let taken = HashSet<String>()
    for (variant in variants) {
        if (!taken.add(variant.value.text)) {
            return variant.ident
        }
    }

    None
}

private func enumExtension(decl: EnumDecl, deserializeBody: Tokens, serializeBody: Tokens): Tokens {
    let typeIdent = decl.identifier
    let typeArgs = typeArgsOf(decl)
    let whereClause = serializableWhereClause(decl)

    quote(
        extend $typeArgs $typeIdent$typeArgs <: Serializable<$typeIdent$typeArgs> $whereClause {
            public static func deserialize(dm: DataModel): $typeIdent$typeArgs {
                $deserializeBody
            }

            public func serialize(): DataModel {
                $serializeBody
            }
        }
    )
}

private func joinedTokens(tokens: Array<Token>): Tokens {
    var joined = Tokens()
    for ((i, token) in tokens |> enumerate) {
        if (i > 0) {
            joined += Tokens(Token(TokenKind.COMMA))
        }
        joined += Tokens(token)
    }

    joined
}

private func report(ident: Token, message: String, hint: String): Tokens {
    diagReport(DiagReportLevel.ERROR, ident.toTokens(), message, hint)

    Tokens()
}

private func report(decl: Decl, message: String, hint: String): Tokens {
    diagReport(DiagReportLevel.ERROR, decl.identifier.toTokens(), message, hint)

    Tokens()
}
