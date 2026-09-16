package lsp_codegen

import std.ast.*
import stdxx.*

struct EnumIr {
    EnumIr(let base: EnumBase, let doc: DocIr, let shape!: EnumShape = Declared, let isOpen!: Bool = false,
        let ident!: String, let variants!: Array<EnumVariantIr>, let derives!: Array<DeriveIr> = []) {}
}

/**
 * Where the constants of an enumeration land.
 */
enum EnumShape {
    /**
     * We declare the type, and the constants live inside it.
     */
    | Declared

    /**
     * The type is declared elsewhere and only the variants are ours. Holds the name of that type.
     *
     * @note they travel as `static prop`s on an interface the type is extended with.
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
    let (ident, shape) = match (cfg.typeMap.bind(enumeration.name)) {
        case Owned(ident) => (ident, Declared)
        case Extern(target) => (enumeration.name, Adopted(target))
        case Aliased(_) | Skipped => return None
    }

    let base = match (enumeration.enumerationType) {
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

    EnumIr(
        base,
        resolveDoc(enumeration),
        shape: shape,
        isOpen: isOpen,
        ident: ident,
        variants: enumeration.values.map {
            it: EnumerationEntry => resolveEnumVariant(it, asConstructor: asConstructors)
        },
        derives: derives
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
        // body
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
        let constValue = adoptedConst.value

        emitDoc(adoptedConst.doc)
        emitln(quote(static prop $constIdent: $targetType { get() { $targetType($constValue) } }))
    }

    private func emitOpenEnum(openEnum: EnumIr): Unit {
        let enumIdent = escapedIdent(openEnum.ident)
        let enumBaseType = openEnum.base.toTokens()

        emit(quote(public struct $enumIdent))
        // body
        blockln {
            =>
                // primary ctor
                emitln(quote(public const $enumIdent(public let value: $enumBaseType) {}))

                for (variant in openEnum.variants) {
                    emitOpenEnumVariant(variant, enumIdent)
                    nl()
                }
        }
    }

    private func emitOpenEnumVariant(openEnumVariant: EnumVariantIr, enumIdent: Token): Unit {
        let enumVariantIdent = escapedIdent(openEnumVariant.ident)
        let enumVariantValue = openEnumVariant.value

        emitDoc(openEnumVariant.doc)
        emitln(quote(public static const $enumVariantIdent: $enumIdent = $enumIdent($enumVariantValue)))
    }

    private func emitClosedEnum(closedEnum: EnumIr): Unit {
        let enumIdent = escapedIdent(closedEnum.ident)

        emit(quote(public enum $enumIdent))
        // body
        blockln {
            => for (variant in closedEnum.variants) {
                emitClosedEnumVariant(variant)
                nl()
            }
        }
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
