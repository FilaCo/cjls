package lsp_codegen

import std.collection.HashMap
import std.fs.Path
import std.io.{ByteBuffer, readToEnd}
import std.unittest.*
import std.unittest.testmacro.*
import stdxx.IntegerOrString

private func enumerationOf(name: String, values: Array<EnumerationEntry>): Enumeration {
    Enumeration(name: name, enumerationType: EnumerationType(name: EnumerationBaseType.Integer), values: values, supportsCustomValues: true)
}

private func configWith(typeMap: TypeMap): Config {
    Config(srcDir: Path("src"), outputPackage: "demo.lsp_types", typeMap: typeMap)
}

private func emitted(enumIr: EnumIr): String {
    let output = ByteBuffer()
    let sut = CjEmitter(output)
    sut.emitEnum(enumIr)
    sut.flush()

    unsafe { String.fromUtf8(readToEnd(output)) }
}

@Test
class ResolveEnumTest {
    @TestCase
    func anUnlistedEnumerationIsDeclaredUnderItsOwnName() {
        // arrange
        let sut = enumerationOf("MessageType", [EnumerationEntry(name: "Error", value: IntegerOrString.Integer(1))])

        // act
        let ir = resolveEnum(configWith(TypeMap()), sut).getOrThrow()

        // assert
        @Expect("MessageType", ir.ident)
        @Expect(match (ir.shape) {
            case Declared => true
            case _ => false
        })
    }

    /**
     * The type belongs to another package, but its constants still have to come from somewhere.
     */
    @TestCase
    func anExternEnumerationAdoptsItsConstantsOntoTheTargetUnderItsMetaModelName() {
        // arrange
        let typeMap = TypeMap(entries: HashMap([("LSPErrorCodes", TypeBinding.Extern("ErrorCode"))]))
        let sut = enumerationOf("LSPErrorCodes",
            [EnumerationEntry(name: "RequestFailed", value: IntegerOrString.Integer(-32803))])

        // act
        let ir = resolveEnum(configWith(typeMap), sut).getOrThrow()

        // assert
        @Expect("LSPErrorCodes", ir.ident)
        @Expect(match (ir.shape) {
            case Adopted(target) => target == "ErrorCode"
            case _ => false
        })
    }

    @TestCase
    func aSkippedEnumerationYieldsNothingToEmit() {
        // arrange
        let typeMap = TypeMap(entries: HashMap([("ErrorCodes", TypeBinding.Skipped)]))
        let sut = enumerationOf("ErrorCodes",
            [EnumerationEntry(name: "ParseError", value: IntegerOrString.Integer(-32700))])

        // act
        let ir = resolveEnum(configWith(typeMap), sut)

        // assert
        @Expect(ir.isNone())
    }

    /**
     * An aliased name is somebody else's type in full - constants included - so there is nothing
     * left for the generator to say about it.
     */
    @TestCase
    func anAliasedEnumerationYieldsNothingToEmit() {
        // arrange
        let typeMap = TypeMap(entries: HashMap([("LSPAny", TypeBinding.Aliased("DataModel"))]))
        let sut = enumerationOf("LSPAny", [EnumerationEntry(name: "Whatever", value: IntegerOrString.Integer(1))])

        // act
        let ir = resolveEnum(configWith(typeMap), sut)

        // assert
        @Expect(ir.isNone())
    }
}

@Test
class ResolveEnumDerivesTest {
    @TestCase
    func aClosedEnumerationDerivesSerializableAsItsValues() {
        // arrange
        let sut = closedStringEnumeration("MarkupKind", [("PlainText", "plaintext"), ("Markdown", "Markdown")])

        // act
        let ir = resolveEnum(configWith(TypeMap()), sut).getOrThrow()

        // assert
        @Expect(!isTransparent(ir))
        @Expect("PlainText", ir.variants[0].ident)
        @Expect(Some(IntegerOrString.String("plaintext")), ir.variants[0].serializable.getOrThrow().value)
        @Expect(ir.variants[1].serializable.getOrThrow().value.isNone())
    }

    /**
     * A variant's name on the wire is compared against the identifier it ends up with, not against
     * the metaModel name it was cased from.
     */
    @TestCase
    func aValueIsGivenWhenCasingMovesTheIdentifierAwayFromIt() {
        // arrange
        let sut = closedStringEnumeration("Kind", [("markdown", "markdown")])

        // act
        let ir = resolveEnum(configWith(TypeMap()), sut).getOrThrow()

        // assert
        @Expect("Markdown", ir.variants[0].ident)
        @Expect(Some(IntegerOrString.String("markdown")), ir.variants[0].serializable.getOrThrow().value)
    }

    @TestCase
    func anIntegerVariantAlwaysGivesItsValue() {
        // arrange
        let sut = Enumeration(name: "MessageType", enumerationType: EnumerationType(name: EnumerationBaseType.Integer),
            values: [EnumerationEntry(name: "Error", value: IntegerOrString.Integer(1))])

        // act
        let ir = resolveEnum(configWith(TypeMap()), sut).getOrThrow()

        // assert
        @Expect(Some(IntegerOrString.Integer(1)), ir.variants[0].serializable.getOrThrow().value)
    }

    @TestCase
    func anOpenEnumerationIsTransparentAndItsConstantsCarryNoMarker() {
        // arrange
        let sut = enumerationOf("ErrorCodes",
            [EnumerationEntry(name: "ParseError", value: IntegerOrString.Integer(-32700))])

        // act
        let ir = resolveEnum(configWith(TypeMap()), sut).getOrThrow()

        // assert
        @Expect(isTransparent(ir))
        @Expect("PARSE_ERROR", ir.variants[0].ident)
        @Expect(ir.variants[0].serializable.isNone())
    }

    @TestCase
    func anAdoptedEnumerationDerivesNothing() {
        // arrange
        let typeMap = TypeMap(entries: HashMap([("LSPErrorCodes", TypeBinding.Extern("ErrorCode"))]))
        let sut = enumerationOf("LSPErrorCodes",
            [EnumerationEntry(name: "RequestFailed", value: IntegerOrString.Integer(-32803))])

        // act
        let ir = resolveEnum(configWith(typeMap), sut).getOrThrow()

        // assert
        @Expect(ir.derives.isEmpty())
        @Expect("REQUEST_FAILED", ir.variants[0].ident)
        @Expect(ir.variants[0].serializable.isNone())
    }

    @TestCase
    func aClosedEnumerationReadsUnknownValuesIntoACatchAllOfItsBaseType() {
        // arrange
        let sut = Enumeration(name: "SymbolKind", enumerationType: EnumerationType(name: EnumerationBaseType.UInteger),
            values: [EnumerationEntry(name: "File", value: IntegerOrString.Integer(1))])

        // act
        let ir = resolveEnum(configWith(TypeMap()), sut).getOrThrow()

        // assert
        let catchAll = ir.catchAll.getOrThrow()
        @Expect("Unknown", catchAll.ident)
        @Expect(catchAll.serializable.other)
    }

    @TestCase
    func onlyAClosedEnumerationGetsACatchAll() {
        // arrange
        let open = enumerationOf("ErrorCodes",
            [EnumerationEntry(name: "ParseError", value: IntegerOrString.Integer(-32700))])
        let typeMap = TypeMap(entries: HashMap([("LSPErrorCodes", TypeBinding.Extern("ErrorCode"))]))
        let adopted = Enumeration(name: "LSPErrorCodes", enumerationType: EnumerationType(name: EnumerationBaseType.Integer),
            values: [EnumerationEntry(name: "RequestFailed", value: IntegerOrString.Integer(-32803))])

        // act & assert
        @Expect(resolveEnum(configWith(TypeMap()), open).getOrThrow().catchAll.isNone())
        @Expect(resolveEnum(configWith(typeMap), adopted).getOrThrow().catchAll.isNone())
    }

    @TestCase
    func aVariantThatTakesTheCatchAllsNameFailsGeneration() {
        // arrange
        let sut = closedStringEnumeration("Kind", [("Unknown", "unknown")])

        // act
        let e = @AssertThrows[IllegalStateException](resolveEnum(configWith(TypeMap()), sut))

        // assert
        @Expect("`Kind` defines `Unknown` itself, which is taken by the catch-all variant", e.message)
    }

    private static func closedStringEnumeration(name: String, entries: Array<(String, String)>): Enumeration {
        Enumeration(
            name: name,
            enumerationType: EnumerationType(name: EnumerationBaseType.String),
            values: entries.map {
                entry: (String, String) => EnumerationEntry(name: entry[0], value: IntegerOrString.String(entry[1]))
            }
        )
    }

    private static func isTransparent(ir: EnumIr): Bool {
        for (derive in ir.derives) {
            if (let Serializable(options) <- derive) {
                return options.transparent
            }
        }

        false
    }
}

@Test
class EmitDeclaredEnumTest {
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
        let actual = emitted(sut)

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
        let actual = emitted(sut)

        // assert
        @PowerAssert(expected, actual)
    }
}

@Test
class EmitAdoptedEnumTest {
    /**
     * The `extend` is what makes the constants reachable as `ErrorCode.REQUEST_FAILED` outside this
     * package - a bare `extend` carrying them directly would not leave it. `sealed` already implies
     * public, so spelling it out earns a `redundant modifier` warning.
     *
     * @note the blank lines inside the block are what the emitter lays down; `cjfmt`, which
     * `main` runs over the output directory, collapses them in the file that lands on disk.
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
        let actual = emitted(sut)

        // assert
        @PowerAssert(expected, actual)
    }
}
