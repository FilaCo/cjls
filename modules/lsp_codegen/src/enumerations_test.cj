package lsp_codegen

import std.collection.HashMap
import std.fs.Path
import std.io.{ByteBuffer, readToEnd}
import std.unittest.*
import std.unittest.testmacro.*
import stdxx.*

private func enumerationOf(name: String, values: Array<EnumerationEntry>): Enumeration {
    Enumeration(name: name, `type`: EnumerationType.Integer, values: values, supportsCustomValues: true)
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
            variants: [EnumVariantIr(DocIr(), ident: "RequestFailed", value: IntegerOrString.Integer(-32803))]
        )

        let expected = """
sealed interface LSPErrorCodes{
    static prop REQUEST_FAILED: ErrorCode { get() { ErrorCode(-32803) } }


}

extend ErrorCode <: LSPErrorCodes { }
"""

        // act
        let actual = emitted(sut)

        // assert
        @PowerAssert(expected, actual)
    }
}
