package lsp_codegen

import std.ast.*
import stdxx.*

struct EnumIr {
    EnumIr(let base: EnumBase, let doc: DocIr, let isOpen!: Bool = false, let ident!: String,
        let variants!: Array<EnumVariantIr>) {}
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
    None
}

extend CjEmitter {
    func emitEnum(enumIr: EnumIr): Unit {
        emitDoc(enumIr.doc)
        if (enumIr.isOpen) {
            emitOpenEnum(enumIr)
        } else {
            emitClosedEnum(enumIr)
        }
    }

    private func emitOpenEnum(openEnum: EnumIr): Unit {
        let enumIdent = Token(IDENTIFIER, openEnum.ident)
        let enumBaseType = openEnum.base.toTokens()

        emit(quote(public struct $enumIdent))
        // body
        block {
            =>
                // primary ctor
                emitln(quote(public const $enumIdent(public let value: $enumBaseType) {}))

                for (variant in openEnum.variants) {
                    emitOpenEnumVariant(variant, enumIdent)
                }
        }
    }

    private func emitOpenEnumVariant(openEnumVariant: EnumVariantIr, enumIdent: Token): Unit {
        let enumVariantIdent = Token(IDENTIFIER, openEnumVariant.ident.toAsciiUpperSnakeCase())
        let enumVariantValue = match (openEnumVariant.value) {
            case IntegerOrString.String(s) => quote(s)
            case Integer(i) => quote(i)
        }

        emitDoc(openEnumVariant.doc)
        emitln(quote(public static const $enumVariantIdent: $enumIdent = $enumIdent($enumVariantValue)))
    }

    private func emitClosedEnumSerializable(): Unit {}

    private func emitClosedEnum(closedEnum: EnumIr): Unit {
        let enumIdent = Token(IDENTIFIER, closedEnum.ident)

        emit(quote(public enum $enumIdent))
        // body
        block {
            => for (variant in closedEnum.variants) {
                emitClosedEnumVariant(variant)
            }
        }
    }

    private func emitClosedEnumVariant(closedEnumVariant: EnumVariantIr): Unit {
        let enumVariantIdent = Token(IDENTIFIER, closedEnumVariant.ident.toAsciiPascalCase())

        emitDoc(closedEnumVariant.doc)
        emit(quote(| $enumVariantIdent}))
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
