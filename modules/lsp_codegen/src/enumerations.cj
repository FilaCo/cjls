package lsp_codegen

import std.ast.*
import stdxx.IntegerOrString

struct EnumIr {
    EnumIr(let base: EnumBase, let doc: DocIr, let shape!: EnumShape = Declared, let isOpen!: Bool = false,
        let ident!: String, let variants!: Array<EnumVariantIr>, let derives!: Array<DeriveIr> = [],
        let catchAll!: ?EnumCatchAllIr = None) {}
}

/**
 * The variant a closed enumeration reads any value it does not define into. The spec allows a
 * client to send such values - a capability's `valueSet` may list kinds newer than ours - and without
 * it one of them fails the whole message.
 */
struct EnumCatchAllIr {
    EnumCatchAllIr(let doc: DocIr, let ident!: String, let serializable!: SerializableMemberOptions) {}
}

const CATCH_ALL_IDENT = "Unknown"

enum EnumShape {
    | Declared

    /**
     * The type is declared elsewhere - this is its name - and only the constants are ours. They
     * travel as `static prop`s on an interface the type is extended with: a bare `extend` would not
     * export them past this package.
     */
    | Adopted(String)
}

struct EnumVariantIr {
    EnumVariantIr(
        let doc: DocIr,
        // unescaped: the resolver compares it with the wire value, the emitter escapes it
        let ident!: String,
        let value!: IntegerOrString,
        let serializable!: ?SerializableMemberOptions = None
    ) {}
}

enum EnumBase {
    | StringBase
    | Int32Base
    | UInt32Base
}

func resolveEnum(cfg: Config, enumeration: Enumeration): ?EnumIr {
    let (ident, shape, declared) = match (cfg.typeMap.bind(enumeration.name)) {
        case Owned(ident) => (ident, Declared, Array<String>())
        case Extern(target, declared) => (enumeration.name, Adopted(target), declared)
        case Aliased(_) | Skipped => return None
    }
    for (name in declared where !enumeration.values.any {it => it.name == name}) {
        throw IllegalStateException("`types.${enumeration.name}.declared` names `${name}`, which it does not have")
    }

    let base = match (enumeration.enumerationType.name) {
        case String => StringBase
        case Integer => Int32Base
        case UInteger => UInt32Base
    }

    let isOpen = enumeration.supportsCustomValues ?? false
    // only a closed enumeration we declare becomes an `enum`: an open one is a struct around its
    // value, and both it and an adopted one carry their constants as `static` members
    let (derives, asConstructors): (Array<DeriveIr>, Bool) = match (shape) {
        case Declared => ([Serializable(SerializableTypeOptions(transparent: isOpen)), DeriveIr.Equatable,
            DeriveIr.Hashable], !isOpen)
        case Adopted(_) => ([], false)
    }

    let variants = enumeration.values
        .filter {it => !declared.contains(it.name)}
        .map {it => resolveEnumVariant(it, asConstructor: asConstructors)}
    var catchAll: ?EnumCatchAllIr = None
    if (asConstructors) {
        if (variants.any {it => it.ident == CATCH_ALL_IDENT}) {
            throw IllegalStateException("`${enumeration.name}` defines `${CATCH_ALL_IDENT}` itself, which is taken by the catch-all variant")
        }
        catchAll = EnumCatchAllIr(
            DocIr(documentation: "A value this version of the protocol does not define."),
            ident: CATCH_ALL_IDENT,
            serializable: SerializableMemberOptions(other: true)
        )
    }

    EnumIr(
        base,
        resolveDoc(enumeration),
        shape: shape,
        isOpen: isOpen,
        ident: ident,
        variants: variants,
        derives: derives,
        catchAll: catchAll
    )
}

private func resolveEnumVariant(entry: EnumerationEntry, asConstructor!: Bool): EnumVariantIr {
    let ident = if (asConstructor) {
        entry.name.toAsciiPascalCase()
    } else {
        entry.name.toAsciiUpperSnakeCase()
    }

    let serializable: ?SerializableMemberOptions = if (!asConstructor) {
        None
    } else if (entry.value == ident) {
        // the macro already puts a variant on the wire under its identifier
        SerializableMemberOptions()
    } else {
        SerializableMemberOptions(value: entry.value)
    }

    EnumVariantIr(resolveDoc(entry), ident: ident, value: entry.value, serializable: serializable)
}

extend CjEmitter {
    func emitEnum(enumIr: EnumIr): Unit {
        emitDoc(enumIr.doc)
        match (enumIr.shape) {
            case Adopted(target) => emitAdoptedVariants(enumIr, target)
            case Declared =>
                emitDerives(enumIr.derives)
                if (enumIr.isOpen) {
                    emitOpenEnum(enumIr)
                } else {
                    emitClosedEnum(enumIr)
                }
        }
    }

    private func emitAdoptedVariants(adopted: EnumIr, target: String): Unit {
        let interfaceIdent = escapedIdent(adopted.ident)
        let targetType = cangjieLex(target)

        emit(quote(sealed interface $interfaceIdent))
        blockln {
            => for (variant in adopted.variants) {
                emitAdoptedVariant(variant, targetType)
                nl()
            }
        }
        nl()
        emitln(quote(extend $targetType <: $interfaceIdent {}))
    }

    private func emitAdoptedVariant(adoptedConst: EnumVariantIr, targetType: Tokens): Unit {
        let constIdent = escapedIdent(adoptedConst.ident)
        let constValue = literalOf(adoptedConst.value)

        emitDoc(adoptedConst.doc)
        emitln(quote(static prop $constIdent: $targetType { get() { $targetType($constValue) } }))
    }

    private func emitOpenEnum(openEnum: EnumIr): Unit {
        let enumIdent = escapedIdent(openEnum.ident)
        let enumBaseType = openEnum.base.toTokens()

        emit(quote(public struct $enumIdent))
        blockln {
            =>
                emitln(quote(public const $enumIdent(public let value: $enumBaseType) {}))

                for (variant in openEnum.variants) {
                    emitOpenEnumVariant(variant, enumIdent)
                    nl()
                }
        }
    }

    private func emitOpenEnumVariant(openEnumVariant: EnumVariantIr, enumIdent: Token): Unit {
        let enumVariantIdent = escapedIdent(openEnumVariant.ident)
        let enumVariantValue = literalOf(openEnumVariant.value)

        emitDoc(openEnumVariant.doc)
        emitln(quote(public static const $enumVariantIdent: $enumIdent = $enumIdent($enumVariantValue)))
    }

    private func emitClosedEnum(closedEnum: EnumIr): Unit {
        let enumIdent = escapedIdent(closedEnum.ident)

        emit(quote(public enum $enumIdent))
        blockln {
            =>
                for (variant in closedEnum.variants) {
                    emitClosedEnumVariant(variant)
                    nl()
                }
                if (let Some(catchAll) <- closedEnum.catchAll) {
                    emitCatchAllVariant(catchAll, closedEnum.base)
                }
        }
    }

    private func emitCatchAllVariant(catchAll: EnumCatchAllIr, base: EnumBase): Unit {
        let ident = escapedIdent(catchAll.ident)
        let marker = catchAll.serializable

        emitDoc(catchAll.doc)
        emitln(quote(| $marker $ident($base)))
    }

    private func emitClosedEnumVariant(closedEnumVariant: EnumVariantIr): Unit {
        let enumVariantIdent = escapedIdent(closedEnumVariant.ident)
        let marker = serializableMarkerOf(closedEnumVariant.serializable)

        emitDoc(closedEnumVariant.doc)
        emitln(quote(| $marker $enumVariantIdent))
    }
}

extend EnumBase <: ToTokens {
    public func toTokens(): Tokens {
        Tokens(match (this) {
            case StringBase => Token(IDENTIFIER, "String")
            case Int32Base => Token(INT32)
            case UInt32Base => Token(UINT32)
        })
    }
}
