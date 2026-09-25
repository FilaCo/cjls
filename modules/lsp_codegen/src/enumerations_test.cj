package lsp_codegen

import std.collection.HashMap
import std.unittest.*
import std.unittest.testmacro.*
import stdxx.IntegerOrString

private func enumerationOf(name: String, base: EnumerationBaseType, entries: Array<(String, IntegerOrString)>,
    isOpen!: Bool = false): Enumeration {
    Enumeration(
        name: name,
        enumerationType: EnumerationType(name: base),
        values: entries.map {it: (String, IntegerOrString) => EnumerationEntry(name: it[0], value: it[1])},
        supportsCustomValues: isOpen
    )
}

private func resolved(enumeration: Enumeration, typeMap!: TypeMap = TypeMap()): ?EnumIr {
    resolveEnum(configOf(typeMap: typeMap), enumeration)
}

private func isTransparent(ir: EnumIr): Bool {
    ir.derives.any {
        derive => match (derive) {
            case Serializable(options) => options.transparent
            case _ => false
        }
    }
}

@Test
class ResolveEnumTest {
    @TestCase
    func aClosedEnumerationIsAnEnumOfItsValuesWithACatchAll() {
        // arrange
        let sut = enumerationOf("MarkupKind", EnumerationBaseType.String,
            [("PlainText", IntegerOrString.String("plaintext")), ("Markdown", IntegerOrString.String("Markdown"))])

        // act
        let ir = resolved(sut).getOrThrow()

        // assert
        @Expect("MarkupKind", ir.ident)
        @Expect(!isTransparent(ir))
        @Expect(Some(IntegerOrString.String("plaintext")), ir.variants[0].serializable.getOrThrow().value)
        @Expect(ir.variants[1].serializable.getOrThrow().value.isNone())
        let catchAll = ir.catchAll.getOrThrow()
        @Expect("Unknown", catchAll.ident)
        @Expect(catchAll.serializable.other)
    }

    /**
     * A variant's name on the wire is compared with the identifier it ends up with, not with the
     * metaModel name it was cased from.
     */
    @TestCase
    func aValueIsGivenWhenCasingMovesTheIdentifierAwayFromIt() {
        // arrange
        let sut = enumerationOf("Kind", EnumerationBaseType.String, [("markdown", IntegerOrString.String("markdown"))])

        // act
        let ir = resolved(sut).getOrThrow()

        // assert
        @Expect("Markdown", ir.variants[0].ident)
        @Expect(Some(IntegerOrString.String("markdown")), ir.variants[0].serializable.getOrThrow().value)
    }

    @TestCase
    func anIntegerVariantAlwaysGivesItsValue() {
        // arrange
        let sut = enumerationOf("MessageType", EnumerationBaseType.Integer, [("Error", IntegerOrString.Integer(1))])

        // act
        let ir = resolved(sut).getOrThrow()

        // assert
        @Expect(Some(IntegerOrString.Integer(1)), ir.variants[0].serializable.getOrThrow().value)
    }

    @TestCase
    func anOpenEnumerationIsATransparentStructOfConstants() {
        // arrange
        let sut = enumerationOf("ErrorCodes", EnumerationBaseType.Integer, [("ParseError", IntegerOrString.Integer(-32700))],
            isOpen: true)

        // act
        let ir = resolved(sut).getOrThrow()

        // assert
        @Expect(isTransparent(ir))
        @Expect("PARSE_ERROR", ir.variants[0].ident)
        @Expect(ir.variants[0].serializable.isNone())
        @Expect(ir.catchAll.isNone())
    }

    @TestCase
    func aValueTheTargetDeclaresItselfIsLeftToIt() {
        // arrange
        let sut = enumerationOf("ErrorCodes", EnumerationBaseType.Integer,
            [("ParseError", IntegerOrString.Integer(-32700)), ("ServerNotInitialized", IntegerOrString.Integer(-32002))])
        let typeMap = TypeMap(entries: HashMap([("ErrorCodes", TypeBinding.Extern("ErrorCode", ["ParseError"]))]))

        // act
        let ir = resolved(sut, typeMap: typeMap).getOrThrow()

        // assert
        @PowerAssert(["SERVER_NOT_INITIALIZED"], ir.variants.map {it: EnumVariantIr => it.ident})
    }

    @TestCase
    func declaringAValueTheEnumerationDoesNotHaveIsRefused() {
        // arrange
        let sut = enumerationOf("ErrorCodes", EnumerationBaseType.Integer, [("ParseError", IntegerOrString.Integer(-32700))])
        let typeMap = TypeMap(entries: HashMap([("ErrorCodes", TypeBinding.Extern("ErrorCode", ["ParseErorr"]))]))

        // act & assert
        @AssertThrows[IllegalStateException](resolved(sut, typeMap: typeMap))
    }

    /**
     * The type belongs to another package, but its constants still have to come from somewhere.
     */
    @TestCase
    func anExternEnumerationAdoptsItsConstantsOntoTheTarget() {
        // arrange
        let sut = enumerationOf("LSPErrorCodes", EnumerationBaseType.Integer,
            [("RequestFailed", IntegerOrString.Integer(-32803))])
        let typeMap = TypeMap(entries: HashMap([("LSPErrorCodes", TypeBinding.Extern("ErrorCode", []))]))

        // act
        let ir = resolved(sut, typeMap: typeMap).getOrThrow()

        // assert
        @Expect("LSPErrorCodes", ir.ident)
        @Expect(match (ir.shape) {
            case Adopted(target) => target == "ErrorCode"
            case _ => false
        })
        @Expect(ir.derives.isEmpty())
        @Expect("REQUEST_FAILED", ir.variants[0].ident)
        @Expect(ir.variants[0].serializable.isNone())
        @Expect(ir.catchAll.isNone())
    }

    /**
     * An aliased name is somebody else's type in full, constants included.
     */
    @TestCase[binding in [TypeBinding.Skipped, TypeBinding.Aliased("DataModel")]]
    func aSkippedOrAliasedEnumerationYieldsNothingToEmit(binding: TypeBinding) {
        // arrange
        let sut = enumerationOf("ErrorCodes", EnumerationBaseType.Integer, [("ParseError", IntegerOrString.Integer(-32700))])

        // act
        let ir = resolved(sut, typeMap: TypeMap(entries: HashMap([("ErrorCodes", binding)])))

        // assert
        @Expect(ir.isNone())
    }

    @TestCase
    func aVariantThatTakesTheCatchAllsNameFailsGeneration() {
        // arrange
        let sut = enumerationOf("Kind", EnumerationBaseType.String, [("Unknown", IntegerOrString.String("unknown"))])

        // act
        let e = @AssertThrows[IllegalStateException](resolved(sut))

        // assert
        @Expect("`Kind` defines `Unknown` itself, which is taken by the catch-all variant", e.message)
    }
}

/**
 * The blank lines inside the blocks are what the emitter lays down; `cjfmt`, which `main` runs over
 * the output, collapses them in the file that lands on disk.
 */
@Test
class EmitEnumTest {
    @TestCase
    func aClosedEnumOpensWithItsDerivesAndMarksOnlyTheVariantsThatNeedIt() {
        // arrange
        let sut = EnumIr(
            EnumBase.StringBase,
            DocIr(),
            ident: "MarkupKind",
            variants: [
                EnumVariantIr(DocIr(), ident: "PlainText", value: IntegerOrString.String("plaintext"),
                    serializable: SerializableMemberOptions(value: IntegerOrString.String("plaintext"))),
                EnumVariantIr(DocIr(), ident: "Markdown", value: IntegerOrString.String("Markdown"),
                    serializable: SerializableMemberOptions())
            ],
            derives: [DeriveIr.Serializable(SerializableTypeOptions()), DeriveIr.Equatable, DeriveIr.Hashable],
            catchAll: EnumCatchAllIr(DocIr(documentation: "Anything else."), ident: "Unknown",
                serializable: SerializableMemberOptions(other: true))
        )
        let expected = """
@DeriveExt[Serializable]
@Derive[Equatable, Hashable]
public enum MarkupKind{
    | @DeriveExtSerializable[value: "plaintext"] PlainText

    | Markdown

    /**
     * Anything else.
     */
    | @DeriveExtSerializable[other] Unknown(String)

}
"""

        // act
        let actual = emittedBy {emitter => emitter.emitEnum(sut)}

        // assert
        @PowerAssert(expected, actual)
    }

    @TestCase
    func anOpenEnumIsATransparentStruct() {
        // arrange
        let sut = EnumIr(
            EnumBase.Int32Base,
            DocIr(),
            isOpen: true,
            ident: "ErrorCodes",
            variants: [EnumVariantIr(DocIr(), ident: "PARSE_ERROR", value: IntegerOrString.Integer(-32700))],
            derives: [DeriveIr.Serializable(SerializableTypeOptions(transparent: true)), DeriveIr.Equatable]
        )
        let expected = """
@DeriveExt[Serializable]
@DeriveExtSerializable[transparent]
@Derive[Equatable]
public struct ErrorCodes{
    public const ErrorCodes(public let value: Int32) { }
    public static const PARSE_ERROR: ErrorCodes = ErrorCodes(- 32700)


}
"""

        // act
        let actual = emittedBy {emitter => emitter.emitEnum(sut)}

        // assert
        @PowerAssert(expected, actual)
    }

    /**
     * `sealed` already implies public; spelling it out earns a `redundant modifier` warning.
     */
    @TestCase
    func adoptedConstantsAreStaticPropsOnAnInterfaceTheTargetIsExtendedWith() {
        // arrange
        let sut = EnumIr(
            EnumBase.Int32Base,
            DocIr(),
            shape: Adopted("ErrorCode"),
            ident: "LSPErrorCodes",
            variants: [EnumVariantIr(DocIr(), ident: "REQUEST_FAILED", value: IntegerOrString.Integer(-32803))]
        )
        let expected = """
sealed interface LSPErrorCodes{
    static prop REQUEST_FAILED: ErrorCode { get() { ErrorCode(- 32803) } }


}

extend ErrorCode <: LSPErrorCodes { }
"""

        // act
        let actual = emittedBy {emitter => emitter.emitEnum(sut)}

        // assert
        @PowerAssert(expected, actual)
    }
}
