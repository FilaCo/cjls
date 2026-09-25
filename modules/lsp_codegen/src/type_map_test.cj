package lsp_codegen

import cjtoml.*
import std.unittest.*
import std.unittest.testmacro.*
import stdx.serialization.serialization.*
import stdxx.serialization.*

/**
 * `unmarshal` reads a path, so the TOML under test has to reach the disk first.
 */
private func typeMapOf(toml: String): TypeMap {
    withConfigDir(toml) {path, _ => unmarshal<TypesOnly>(path.toString()).typeMap}
}

private struct TypesOnly <: Serializable<TypesOnly> {
    TypesOnly(let typeMap: TypeMap) {}

    public static func deserialize(dm: DataModel): TypesOnly {
        TypesOnly(TypeMap.deserialize(dm.asStructOrThrow().getOrThrow("types")))
    }

    public func serialize(): DataModel {
        throw UnsupportedException()
    }
}

@Test
class TypeMapTest {
    @TestCase
    func anUnlistedNameIsOursToDeclareUnderItsOwnName() {
        // act
        let binding = TypeMap().bind("SymbolKind")

        // assert
        @Expect(match (binding) {
            case Owned(ident) => ident == "SymbolKind"
            case _ => false
        })
    }

    @TestCase
    func anAliasedNameKeepsItsMetaModelSpelling() {
        // arrange
        let sut = typeMapOf("[types.LSPAny]\nalias = \"DataModel\"\n")

        // act
        let binding = sut.bind("LSPAny")

        // assert
        @Expect("LSPAny", binding.typeNameOf("LSPAny") ?? "")
        @PowerAssert(["LSPAny"], sut.aliases().map {it: (String, String) => it[0]})
        @PowerAssert(["DataModel"], sut.aliases().map {it: (String, String) => it[1]})
    }

    @TestCase
    func anExternNameResolvesToItsTargetAndIsNotAliased() {
        // arrange
        let sut = typeMapOf("[types.LSPErrorCodes]\nextern = \"ErrorCode\"\n")

        // act
        let binding = sut.bind("LSPErrorCodes")

        // assert
        @Expect("ErrorCode", binding.typeNameOf("LSPErrorCodes") ?? "")
        @Expect(sut.aliases().isEmpty())
    }

    @TestCase
    func anExternNameListsTheValuesItsTargetDeclares() {
        // arrange
        let sut = typeMapOf("[types.ErrorCodes]\nextern = \"ErrorCode\"\ndeclared = [\"ParseError\", \"InternalError\"]\n")

        // act
        let binding = sut.bind("ErrorCodes")

        // assert
        @Expect(match (binding) {
            case Extern(target, declared) => target == "ErrorCode" && declared == ["ParseError", "InternalError"]
            case _ => false
        })
    }

    @TestCase
    func aSkippedNameHasNoCangjieCounterpart() {
        // arrange
        let sut = typeMapOf("[types.ErrorCodes]\nskip = true\n")

        // act
        let binding = sut.bind("ErrorCodes")

        // assert
        @Expect(binding.typeNameOf("ErrorCodes").isNone())
    }

    @TestCase
    func aRenamedNameIsStillOursToDeclare() {
        // arrange
        let sut = typeMapOf("[types.LanguageKind]\nrename = \"LanguageId\"\n")

        // act
        let binding = sut.bind("LanguageKind")

        // assert
        @Expect("LanguageId", binding.typeNameOf("LanguageKind") ?? "")
        @Expect(sut.aliases().isEmpty())
    }

    /**
     * A config line the generator cannot act on is an error here rather than a surprise in the
     * generated files: an empty entry would silently declare the type, a blank target emit
     * `public type LSPAny = `.
     */
    @TestCase[row in [
        ("[types.LSPAny]\nalias = \"DataModel\"\nskip = true\n",
            "`types.LSPAny` sets more than one of `rename`, `alias`, `extern`, `skip`"),
        ("[types.LSPAny]\n[types.ErrorCodes]\nskip = true\n",
            "`types.LSPAny` sets none of `rename`, `alias`, `extern`, `skip`"),
        ("[types.LSPAny]\naliaz = \"DataModel\"\n", "unknown field \"aliaz\""),
        ("[types.LSPAny]\nalias = \"   \"\n", "`types.LSPAny.alias` must not be empty"),
        ("[types.LSPAny]\nalias = \"DataModel\"\ndeclared = [\"X\"]\n", "`types.LSPAny.declared` goes only with `extern`")
    ]]
    func anEntryThatIsNotExactlyOneBindingIsRefused(row: (String, String)) {
        // arrange
        let (toml, message) = row

        // act
        let e = @AssertThrows[DataModelException](typeMapOf(toml))

        // assert
        @Expect(message, e.message)
    }
}
