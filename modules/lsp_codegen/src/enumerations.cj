package lsp_codegen

import std.ast.*
import stdxx.*

struct EnumIr {
    EnumIr(let base: EnumBase, let doc: DocIr, let shape!: EnumShape = Declared, let isOpen!: Bool = false,
        let ident!: String, let variants!: Array<EnumVariantIr>) {}
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
    EnumVariantIr(let doc: DocIr, let ident!: String, let value!: IntegerOrString) {}
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

    let base = match (enumeration.`type`) {
        case String => StringBase
        case Integer => Int32Base
        case UInteger => UInt32Base
    }

    EnumIr(
        base,
        resolveDoc(enumeration),
        shape: shape,
        isOpen: enumeration.supportsCustomValues ?? false,
        ident: ident,
        variants: enumeration.values.map {it: EnumerationEntry => resolveEnumVariant(it)}
    )
}

private func resolveEnumVariant(entry: EnumerationEntry): EnumVariantIr {
    EnumVariantIr(resolveDoc(entry), ident: entry.name, value: entry.value)
}

extend CjEmitter {
    func emitEnum(enumIr: EnumIr): Unit {
        emitDoc(enumIr.doc)
        match (enumIr.shape) {
            case Adopted(target) => emitAdoptedVariants(enumIr, target)
            case Declared => withDerivings([DerivingIr.Equatable, DerivingIr.Hashable]) {
                => if (enumIr.isOpen) {
                    emitOpenEnum(enumIr)
                } else {
                    emitClosedEnum(enumIr)
                }
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
        let constIdent = Token(IDENTIFIER, adoptedConst.ident.toAsciiUpperSnakeCase())
        let constValue = valueToken(adoptedConst.value)

        emitDoc(adoptedConst.doc)
        emitln(quote(static prop $constIdent: $targetType { get() { $targetType($constValue) } }))
    }

    private func emitOpenEnum(openEnum: EnumIr): Unit {
        let enumIdent = Token(IDENTIFIER, openEnum.ident)
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

        // extensions
        emitOpenEnumSerializable(openEnum)
    }

    private func emitOpenEnumVariant(openEnumVariant: EnumVariantIr, enumIdent: Token): Unit {
        let enumVariantIdent = Token(IDENTIFIER, openEnumVariant.ident.toAsciiUpperSnakeCase())
        let enumVariantValue = valueToken(openEnumVariant.value)

        emitDoc(openEnumVariant.doc)
        emitln(quote(public static const $enumVariantIdent: $enumIdent = $enumIdent($enumVariantValue)))
    }

    private func emitOpenEnumSerializable(openEnum: EnumIr): Unit {
        let enumIdent = escapedIdent(openEnum.ident)
        emit(quote(extend $enumIdent <: Serializable<$enumIdent>))
        blockln {
            =>
                emitln(quote(public static func deserialize(dm: DataModel): $enumIdent))
                blockln {
                    =>
                        let dataModelCast = match (openEnum.base) {
                            case Int32Base  => quote(Int32(dm.asIntOrThrow()))
                            case UInt32Base => quote(UInt32(dm.asIntOrThrow()))
                            case StringBase => quote(dm.asStringOrThrow())
                        }


                        emitln(quote($enumIdent($dataModelCast)))
                }
                emitln(quote(public func serialize(): DataModel))
                blockln {
                    =>
                        let serializeBody = match (openEnum.base) {
                            case Int32Base | UInt32Base => quote(DataModelInt(Int64(value)))
                            case StringBase => quote(DataModelString(value))
                        }
                        emitln(serializeBody)
                }
        }
    }

    private func emitClosedEnumSerializable(closedEnum: EnumIr): Unit {
        let enumIdent = escapedIdent(closedEnum.ident)
        emit(quote(extend $enumIdent <: Serializable<$enumIdent>))
        blockln {
            =>
                emitln(quote(public static func deserialize(dm: DataModel): $enumIdent))
                blockln {
                    =>
                        let dataModelCast = match (closedEnum.base) {
                            case Int32Base | UInt32Base => quote(dm.asIntOrThrow())
                            case StringBase => quote(dm.asStringOrThrow())
                        }

                        emitln(quote(match($(dataModelCast))))
                        block {
                            => for (variant in closedEnum.variants) {
                                let valueToken = valueToken(variant.value)
                                let identToken = escapedIdent(variant.ident.toAsciiPascalCase())
                                emitln(quote(case $valueToken => $identToken))
                            }

                            emitln(quote(case v => throw DataModelException("unexpected variant ${v}")))
                        }
                }
                emitln(quote(public func serialize(): DataModel))
                blockln {
                    =>
                        let dataModelType = match (closedEnum.base) {
                            case Int32Base | UInt32Base => quote(DataModelInt)
                            case StringBase => quote(DataModelString)
                        }
                        emitln(quote(match(this)))
                        block {
                            => for (variant in closedEnum.variants) {
                                let identToken = escapedIdent(variant.ident.toAsciiPascalCase())
                                let valueToken = valueToken(variant.value)
                                emitln(quote(case $identToken => $dataModelType($valueToken)))
                            }
                        }
                }
        }
    }

    private func emitClosedEnum(closedEnum: EnumIr): Unit {
        let enumIdent = Token(IDENTIFIER, closedEnum.ident)

        emit(quote(public enum $enumIdent))
        // body
        blockln {
            => for (variant in closedEnum.variants) {
                emitClosedEnumVariant(variant)
                nl()
            }
        }
        // extensions
        emitClosedEnumSerializable(closedEnum)
    }

    private func emitClosedEnumVariant(closedEnumVariant: EnumVariantIr): Unit {
        let enumVariantIdent = escapedIdent(closedEnumVariant.ident.toAsciiPascalCase())

        emitDoc(closedEnumVariant.doc)
        emitln(quote(| $enumVariantIdent))
    }
}

private func valueToken(value: IntegerOrString): Token {
    match (value) {
        case IntegerOrString.String(s) => Token(STRING_LITERAL, s)
        case Integer(i) => Token(INTEGER_LITERAL, i.toString())
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
