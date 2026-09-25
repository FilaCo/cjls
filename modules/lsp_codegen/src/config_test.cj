package lsp_codegen

import std.env.getTempDirectory
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import stdx.serialization.serialization.*

/**
 * Runs `body` with the path of `cfg` written as `lsp_codegen.toml` into a throwaway directory, and
 * that directory - `manifest`, when given, is its `cjpm.toml`.
 */
func withConfigDir<T>(cfg: String, manifest!: ?String = None, body!: (Path, Path) -> T): T {
    let dir = Directory.createTemp(getTempDirectory())
    try {
        if (let Some(m) <- manifest) {
            File.writeTo(dir.join("cjpm.toml"), m.toArray())
        }
        let cfgPath = dir.join("lsp_codegen.toml")
        File.writeTo(cfgPath, cfg.toArray())

        body(cfgPath, dir)
    } finally {
        remove(dir, recursive: true)
    }
}

/**
 * A config as `Config.load` would make it, for `demo.lsp_types` under `src`.
 */
func configOf(typeMap!: TypeMap = TypeMap()): Config {
    Config(srcDir: Path("src"), outputPackage: "demo.lsp_types", typeMap: typeMap)
}

private let DEMO_MANIFEST = "[package]\nname = \"demo\"\n"

private let LSP_TYPES_CONFIG = "[general]\noutput-subpackage = \"lsp_types\"\n"

@Test
class ConfigLoadTest {
    /**
     * `(src-dir in cjpm.toml, src-dir in the config, the directory expected)`: the config wins over
     * the manifest, which wins over `src`; cjpm writes `""` for unset, so a blank value falls through;
     * a relative one resolves against the config's directory, not the cwd.
     */
    @TestCase[row in [
        ("", "", "src"),
        ("src-dir = \"sources\"\n", "", "sources"),
        ("src-dir = \"sources\"\n", "src-dir = \"generated\"\n", "generated"),
        ("src-dir = \"\"\n", "", "src"),
        ("src-dir = \"sources\"\n", "src-dir = \"\"\n", "sources"),
        ("", "src-dir = \"   \"\n", "src"),
        ("", "src-dir = \"./nested/../src\"\n", "src")
    ]]
    func theSrcDirComesFromTheConfigThenTheManifestThenTheDefault(row: (String, String, String)) {
        // arrange
        let (manifestSrcDir, cfgSrcDir, expected) = row
        let manifest = DEMO_MANIFEST + manifestSrcDir
        let cfg = "[general]\n${cfgSrcDir}output-subpackage = \"lsp_types\"\n"

        withConfigDir(cfg, manifest: manifest) {
            cfgPath, dir =>
                // act
                let sut = Config.load(cfgPath)

                // assert
                @Expect("demo.lsp_types", sut.outputPackage)
                @Expect(dir.join(expected).join("lsp_types").toString(), sut.outputDir.toString())
        }
    }

    @TestCase
    func anAbsoluteSrcDirIsLeftAlone() {
        // arrange
        let cfg = "[general]\nsrc-dir = \"/tmp/elsewhere\"\noutput-subpackage = \"lsp_types\"\n"

        withConfigDir(cfg, manifest: DEMO_MANIFEST) {
            cfgPath, _ =>
                // act
                let sut = Config.load(cfgPath)

                // assert
                @Expect(Path("/tmp/elsewhere").join("lsp_types").toString(), sut.outputDir.toString())
        }
    }

    @TestCase
    func aDottedSubpackageBecomesNestedDirectories() {
        // arrange
        let cfg = "[general]\noutput-subpackage = \"lsp.types\"\n"

        withConfigDir(cfg, manifest: DEMO_MANIFEST) {
            cfgPath, dir =>
                // act
                let sut = Config.load(cfgPath)

                // assert
                @Expect("demo.lsp.types", sut.outputPackage)
                @Expect(dir.join("src").join("lsp").join("types").toString(), sut.outputDir.toString())
        }
    }

    @TestCase
    func importsDefaultToNoneAndTypesToAnEmptyMap() {
        withConfigDir(LSP_TYPES_CONFIG, manifest: DEMO_MANIFEST) {
            cfgPath, _ =>
                // act
                let sut = Config.load(cfgPath)

                // assert
                @Expect(sut.imports.isEmpty())
                @Expect("SymbolKind", sut.typeMap.bind("SymbolKind").typeNameOf("SymbolKind") ?? "")
        }
    }

    @TestCase
    func importsAndTypesAreReadFromTheConfig() {
        // arrange
        let cfg = LSP_TYPES_CONFIG + "imports = [\"jsonrpc.*\"]\n[types.ErrorCodes]\nskip = true\n"

        withConfigDir(cfg, manifest: DEMO_MANIFEST) {
            cfgPath, _ =>
                // act
                let sut = Config.load(cfgPath)

                // assert
                @PowerAssert(["jsonrpc.*"], sut.imports.toArray())
                @Expect(sut.typeMap.bind("ErrorCodes").typeNameOf("ErrorCodes").isNone())
        }
    }

    @TestCase
    func aBlankOutputSubpackageThrows() {
        // arrange
        let cfg = "[general]\noutput-subpackage = \"   \"\n"

        withConfigDir(cfg, manifest: DEMO_MANIFEST) {
            cfgPath, _ =>
                // act
                let e = @AssertThrows[ConfigException](Config.load(cfgPath))

                // assert
                @Expect("`output-subpackage` must not be empty", e.message)
        }
    }

    @TestCase
    func aMissingManifestThrowsBecauseTheRootPackageIsUnknown() {
        withConfigDir(LSP_TYPES_CONFIG) {
            cfgPath, _ =>
                // act
                let e = @AssertThrows[ConfigException](Config.load(cfgPath))

                // assert
                @Expect("cannot tell the root package of `lsp_types`", e.message)
        }
    }

    @TestCase
    func aWronglyTypedSrcDirThrowsRatherThanFallingBack() {
        // arrange
        let cfg = "[general]\nsrc-dir = 42\noutput-subpackage = \"lsp_types\"\n"

        withConfigDir(cfg, manifest: DEMO_MANIFEST) {
            cfgPath, _ =>
                // act
                let e = @AssertThrows[DataModelException](Config.load(cfgPath))

                // assert
                @Expect("Invalid `src-dir` field type", e.message)
        }
    }
}

@Test
class ConfigPathsTest {
    @TestCase
    func aBareFilenameResolvesToTheCwd() {
        // act
        let sut = parentDirOf(Path("lsp_codegen.toml"))

        // assert
        @Expect(!sut.isEmpty())
        @Expect("src", Path("src").resolveAgainst(sut).toString())
    }

    @TestCase
    func aPathWithADirectoryKeepsIt() {
        // act
        let sut = parentDirOf(Path("modules/cjls/lsp_codegen.toml"))

        // assert
        @Expect("modules/cjls", sut.toString())
    }

    @TestCase[row in [("src", "/base/src"), ("./nested/../src", "/base/src"), ("/elsewhere/src", "/elsewhere/src")]]
    func aPathResolvesAgainstABaseUnlessItIsAbsolute(row: (String, String)) {
        // arrange
        let (path, expected) = row

        // act
        let sut = Path(path).resolveAgainst(Path("/base"))

        // assert
        @Expect(expected, sut.toString())
    }
}
