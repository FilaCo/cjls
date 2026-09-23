package lsp_codegen

import cjtoml.*
import std.env.getTempDirectory
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import stdx.serialization.serialization.*
import stdxx.*

/**
 * `unmarshal` reads a path, so the TOML under test has to reach the disk first.
 */
private func typeMapOf(toml: String): TypeMap {
    let dir = Directory.createTemp(getTempDirectory())
    try {
        let path = dir.join("types.toml")
        File.writeTo(path, toml.toArray())

        unmarshal<TypesOnly>(path.toString()).typeMap
    } finally {
        remove(dir, recursive: true)
    }
}

private struct TypesOnly <: Serializable<TypesOnly> {
    TypesOnly(let typeMap: TypeMap) {}

    public static func deserialize(dm: DataModel): TypesOnly {
        TypesOnly(TypeMap.deserialize(dm.asStructOrThrow().getOrThrow("types")))
    }

    public func serialize(): DataModel {
        throw UnsupportedException("TypesOnly serialization is not supported.")
    }
}

@Test
class TypeMapTest {
    @TestCase
    func anUnlistedNameIsOursToDeclareUnderItsOwnName() {
        // arrange
        let sut = TypeMap()

        // act
        let binding = sut.bind("SymbolKind")

        // assert
        @Expect("SymbolKind", binding.typeNameOf("SymbolKind") ?? "")
        @Expect(match (binding) {
            case Owned(_) => true
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

    @TestCase
    func settingTwoBindingsForOneNameThrows() {
        // arrange
        let cfg = "[types.LSPAny]\nalias = \"DataModel\"\nskip = true\n"

        // act
        let e = @AssertThrows[DataModelException](typeMapOf(cfg))

        // assert
        @Expect("`types.LSPAny` sets more than one of `rename`, `alias`, `extern`, `skip`", e.message)
    }

    /**
     * A name listed with no binding under it reads as an intent the generator cannot act on, so it
     * is louder to reject it than to silently declare the type ourselves.
     */
    @TestCase
    func anEmptyEntryThrowsRatherThanBeingIgnored() {
        // arrange
        let cfg = "[types.LSPAny]\n[types.ErrorCodes]\nskip = true\n"

        // act
        let e = @AssertThrows[DataModelException](typeMapOf(cfg))

        // assert
        @Expect("`types.LSPAny` sets none of `rename`, `alias`, `extern`, `skip`", e.message)
    }

    @TestCase
    func aMisspelledKeyThrowsRatherThanBeingIgnored() {
        // arrange
        let cfg = "[types.LSPAny]\naliaz = \"DataModel\"\n"

        // act
        let e = @AssertThrows[DataModelException](typeMapOf(cfg))

        // assert
        @Expect("unknown field \"aliaz\"", e.message)
    }

    @TestCase
    func aBlankTargetThrows() {
        // arrange
        let cfg = "[types.LSPAny]\nalias = \"   \"\n"

        // act
        let e = @AssertThrows[DataModelException](typeMapOf(cfg))

        // assert
        @Expect("`types.LSPAny.alias` must not be empty", e.message)
    }
}
