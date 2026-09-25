macro package stdxx.deriving

import std.ast.*
import std.collection.*

func deriveSerializableEnum(decl: EnumDecl): Tokens {
    let (typeOptions, variantOptions) = collectMarkers()
    if (typeOptions.transparent) {
        return report(decl, "`transparent` does not apply to an enum", "it belongs on a struct or a class with one field")
    }
    if (typeOptions.value.isSome()) {
        return report(decl, "`value` on an enum belongs on its variants", "move it onto the variant it names")
    }

    let variants = ArrayList<DerivedVariant>()
    var other: ?DerivedVariant = None
    for (ctor in decl.constructors) {
        let ident = ctor.identifier
        let options = variantOptions.get(ident.value) ?? MarkerOptions()
        let payloadTypes = ctor.typeArguments.toArray()

        let variant = DerivedVariant(
            ident: ident,
            value: options.value ?? WireValue.ofString(stripBackquotes(ident.value)),
            payloadTypes: payloadTypes.map {payloadType => payloadType.toTokens()},
            payloadShapes: payloadTypes.map {payloadType => shapeOf(payloadType)},
            payloadNames: options.payload
        )
        if (!options.other) {
            variants.add(variant)
            continue
        }

        if (other.isSome()) {
            return report(ident, "an enum takes one `other` variant", "`${other.getOrThrow().ident.value}` already is")
        }
        if (options.value.isSome() || !options.payload.isEmpty()) {
            return report(ident, "an `other` variant takes no `value` or `payload`",
                "it has no value of its own - it holds whatever the wire carried")
        }
        if (payloadTypes.size != 1) {
            return report(ident, "an `other` variant needs exactly one payload",
                "it is where the unrecognised value goes, e.g. `Unknown(Int32)`")
        }
        other = variant
    }

    if (variants.isEmpty()) {
        return report(decl, "`@DeriveExt[Serializable]` needs at least one variant besides `other`",
            "there is nothing to recognise")
    }

    // two variants of one value would be indistinguishable, and the earlier one would answer for both
    if (let Some(clash) <- firstDuplicate(variants.map {variant => (variant.value.text, variant.ident)}.toArray())) {
        return report(clash, "two variants share the same value on the wire", "give one of them a different `value:`")
    }

    let isScalar = variants.all {variant => variant.payloadTypes.isEmpty()}
    if (let Some(o) <- other) {
        if (typeOptions.tag.isSome() || !isScalar) {
            return report(o.ident, "`other` applies only to an enum whose variants are plain values",
                "a tagged or an untagged enum has no single value to fall back on")
        }
    }

    match (typeOptions.tag) {
        case Some(tag) => taggedEnumExtension(decl, variants, tag, typeOptions.skipNone)
        case None =>
            if (isScalar) {
                scalarEnumExtension(decl, variants, other)
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
    func payloadBindings(): Array<Tokens> {
        Array(payloadTypes.size) {i => Tokens(Token(TokenKind.IDENTIFIER, "p${i}"))}
    }
}

private func isIntegerType(tokens: Tokens): Bool {
    if (tokens.size != 1) {
        return false
    }

    match (tokens[0].kind) {
        case TokenKind.INT8 | TokenKind.INT16 | TokenKind.INT32 | TokenKind.INT64 | TokenKind.INTNATIVE
            | TokenKind.UINT8 | TokenKind.UINT16 | TokenKind.UINT32 | TokenKind.UINT64 | TokenKind.UINTNATIVE => true
        case _ => false
    }
}

/**
 * Variants without a payload are the value itself - a string, or an integer when `value:` says so.
 */
private func scalarEnumExtension(decl: EnumDecl, variants: ArrayList<DerivedVariant>, other: ?DerivedVariant): Tokens {
    let isInteger = variants[0].value.isInteger
    if (let Some(variant) <- variants.filter {variant => variant.value.isInteger != isInteger}.first) {
        return report(
            decl,
            "`@DeriveExt[Serializable]` needs every `value:` of an enum to be of one kind",
            "`${variant.ident.value}` breaks the string/integer choice the other variants made"
        )
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
    var fallback = quote(case value => throw DataModelException($unexpected + value.toString()))
    if (let Some(o) <- other) {
        let payloadType = o.payloadTypes[0]
        if (isIntegerType(payloadType) != isInteger) {
            return report(
                o.ident,
                "the payload of `other` has to be of the kind the values are",
                "the values are ${if (isInteger) { "integers" } else { "strings" }}, `${payloadType.toString()}` is not"
            )
        }

        let ident = o.ident
        // read through the payload's own `Serializable`: it narrows the `Int64` the reader matched on, and
        // throws on a value that does not fit instead of wrapping it
        fallback = quote(case _ => $ident($payloadType.deserialize(dm)))
        writeCases += quote(
            case $ident(payload) => payload.serialize()
        )
    }

    serializableExtension(
        decl,
        quote(
            match ($reader) {
                $readCases
                $fallback
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
 * A variant with one payload is that payload alone; one with several is a tuple, which travels the
 * way JSON spells one - an array holding the payloads in order, of exactly that length.
 *
 * Any exception means "not this variant", not just a `DataModelException`: reading an `Int32` out
 * of a value too large for it throws `OverflowException`, and a narrower variant failing that way
 * is exactly what the next one is for.
 */
private func untaggedEnumExtension(decl: EnumDecl, variants: ArrayList<DerivedVariant>): Tokens {
    var attempts = Tokens()
    var writeCases = Tokens()
    for (variant in variants) {
        let ident = variant.ident
        match (variant.payloadTypes.size) {
            case 0 => return report(
                decl,
                "an untagged `@DeriveExt[Serializable]` enum needs a payload on every variant",
                "`${ident.value}` carries none - add `@DeriveExtSerializable[tag: \"...\"]` to make it tagged"
            )
            case 1 =>
                let payloadType = variant.payloadTypes[0]
                attempts += quote(
                    try {
                        return $ident($payloadType.deserialize(dm))
                    } catch (_: Exception) {}
                )
                writeCases += quote(
                    case $ident(payload) => payload.serialize()
                )
            case arity =>
                let bindings = variant.payloadBindings()
                let readArgs = commaSeparated(
                    Array(arity) {
                        i =>
                            let payloadType = variant.payloadTypes[i]
                            let index = Token(TokenKind.INTEGER_LITERAL, "${i}")
                            quote($payloadType.deserialize(items[$index]))
                    }
                )
                // one `add` per payload rather than an `ArrayList` literal: the expansion must not
                // depend on the caller importing `std.collection`
                var writeItems = Tokens()
                for (binding in bindings) {
                    writeItems += quote(
                        items.add($binding.serialize())
                    )
                }
                let size = Token(TokenKind.INTEGER_LITERAL, "${arity}")
                let pattern = commaSeparated(bindings)
                attempts += quote(
                    try {
                        let items = dm.asSeqOrThrow().getItems()
                        if (items.size == $size) {
                            return $ident($readArgs)
                        }
                    } catch (_: Exception) {}
                )
                writeCases += quote(
                    case $ident($pattern) =>
                        let items = DataModelSeq()
                        $writeItems
                        items
                )
        }
    }
    let unexpected = Token(TokenKind.STRING_LITERAL, "no `${decl.identifier.value}` variant matched the value")

    serializableExtension(
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

        let nameLiterals = variant.payloadNames.map {name => Token(TokenKind.STRING_LITERAL, name)}
        let readArgs = commaSeparated(Array(nameLiterals.size) {i => variant.payloadShapes[i].reader(nameLiterals[i])})
        var writeFields = Tokens()
        for ((i, shape) in variant.payloadShapes |> enumerate) {
            writeFields += shape.writer(nameLiterals[i], bindings[i], skipNone)
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
            let pattern = commaSeparated(bindings)
            quote(
                case $ident($pattern) => DataModelStruct().add(field($tagLiteral, $literal))$writeFields
            )
        }
    }
    let unexpected = Token(TokenKind.STRING_LITERAL, "unexpected `${decl.identifier.value}` ${tag}: ")

    serializableExtension(
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
