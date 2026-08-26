package lsp_codegen

import std.env.getTempDirectory
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import stdx.serialization.serialization.*

/**
 * Runs `body` against a throwaway directory holding `cfg` as `lsp_codegen.toml` and, when given,
 * `manifest` as `cjpm.toml` next to it. `body` receives the config path.
 */
private func withConfigDir(cfg: String, manifest!: ?String = None, body!: (Path, Path) -> Unit): Unit {
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

private let DEMO_MANIFEST = "[package]\nname = \"demo\"\n"

@Test
class ConfigLoadTest {
    @TestCase
    func inheritsSrcDirAndRootPackageFromTheManifest() {
        // arrange
        let cfg = "[general]\noutput-subpackage = \"lsp_types\"\n"

        withConfigDir(cfg, manifest: DEMO_MANIFEST) {
            cfgPath, dir =>
                // act
                let sut = Config.load(cfgPath)

                // assert
                @Expect("demo.lsp_types", sut.outputPackage)
                @Expect(dir.join("src").join("lsp_types").toString(), sut.outputDir.toString())
        }
    }

    @TestCase
    func honoursSrcDirFromTheManifest() {
        // arrange
        let manifest = "[package]\nname = \"demo\"\nsrc-dir = \"sources\"\n"
        let cfg = "[general]\noutput-subpackage = \"lsp_types\"\n"

        withConfigDir(cfg, manifest: manifest) {
            cfgPath, dir =>
                // act
                let sut = Config.load(cfgPath)

                // assert
                @Expect(dir.join("sources").join("lsp_types").toString(), sut.outputDir.toString())
        }
    }

    @TestCase
    func theConfigSrcDirWinsOverTheManifest() {
        // arrange
        let manifest = "[package]\nname = \"demo\"\nsrc-dir = \"sources\"\n"
        let cfg = "[general]\nsrc-dir = \"generated\"\noutput-subpackage = \"lsp_types\"\n"

        withConfigDir(cfg, manifest: manifest) {
            cfgPath, dir =>
                // act
                let sut = Config.load(cfgPath)

                // assert
                @Expect(dir.join("generated").join("lsp_types").toString(), sut.outputDir.toString())
        }
    }

    /**
     * cjpm writes `""` to mean "unset", so a blank value must fall through to the next source
     * rather than resolving to a directory whose name is the empty string.
     */
    @TestCase
    func anEmptySrcDirInTheManifestFallsBackToSrc() {
        // arrange
        let manifest = "[package]\nname = \"demo\"\nsrc-dir = \"\"\n"
        let cfg = "[general]\noutput-subpackage = \"lsp_types\"\n"

        withConfigDir(cfg, manifest: manifest) {
            cfgPath, dir =>
                // act
                let sut = Config.load(cfgPath)

                // assert
                @Expect(dir.join("src").join("lsp_types").toString(), sut.outputDir.toString())
        }
    }

    @TestCase
    func anEmptySrcDirInTheConfigFallsBackToTheManifest() {
        // arrange
        let manifest = "[package]\nname = \"demo\"\nsrc-dir = \"sources\"\n"
        let cfg = "[general]\nsrc-dir = \"\"\noutput-subpackage = \"lsp_types\"\n"

        withConfigDir(cfg, manifest: manifest) {
            cfgPath, dir =>
                // act
                let sut = Config.load(cfgPath)

                // assert
                @Expect(dir.join("sources").join("lsp_types").toString(), sut.outputDir.toString())
        }
    }

    @TestCase
    func aBlankSrcDirIsTreatedAsAbsent() {
        // arrange
        let cfg = "[general]\nsrc-dir = \"   \"\noutput-subpackage = \"lsp_types\"\n"

        withConfigDir(cfg, manifest: DEMO_MANIFEST) {
            cfgPath, dir =>
                // act
                let sut = Config.load(cfgPath)

                // assert
                @Expect(dir.join("src").join("lsp_types").toString(), sut.outputDir.toString())
        }
    }

    /**
     * The whole point of reading the config through its own directory: the output must not move
     * when the generator is run from a different cwd.
     */
    @TestCase
    func aRelativeSrcDirResolvesAgainstTheConfigDirNotTheCwd() {
        // arrange
        let cfg = "[general]\nsrc-dir = \"./nested/../src\"\noutput-subpackage = \"lsp_types\"\n"

        withConfigDir(cfg, manifest: DEMO_MANIFEST) {
            cfgPath, dir =>
                // act
                let sut = Config.load(cfgPath)

                // assert
                @Expect(dir.join("src").join("lsp_types").toString(), sut.outputDir.toString())
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
        // arrange
        let cfg = "[general]\noutput-subpackage = \"lsp_types\"\n"

        withConfigDir(cfg) {
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
class ConfigDirOfTest {
    /**
     * `Path("lsp_codegen.toml").parent` is empty, and joining onto an empty path throws — so a
     * config named without a directory has to resolve to the cwd explicitly.
     */
    @TestCase
    func aBareFilenameResolvesToTheCwd() {
        // arrange
        let cfgPath = Path("lsp_codegen.toml")

        // act
        let sut = parentDirOf(cfgPath)

        // assert — an empty parent would throw on the join that `load` does next
        @Expect(false, sut.isEmpty())
        @Expect("src", Path("src").resolveAgainst(sut).toString())
    }

    @TestCase
    func aPathWithADirectoryKeepsIt() {
        // act
        let sut = parentDirOf(Path("modules/cjls/lsp_codegen.toml"))

        // assert
        @Expect("modules/cjls", sut.toString())
    }
}

@Test
class ResolveAgainstTest {
    @TestCase
    func joinsARelativePathOntoTheBase() {
        // act
        let sut = Path("src").resolveAgainst(Path("/base"))

        // assert
        @Expect("/base/src", sut.toString())
    }

    @TestCase
    func normalizesWhileJoining() {
        // act
        let sut = Path("./nested/../src").resolveAgainst(Path("/base"))

        // assert
        @Expect("/base/src", sut.toString())
    }

    @TestCase
    func ignoresTheBaseForAnAbsolutePath() {
        // act
        let sut = Path("/elsewhere/src").resolveAgainst(Path("/base"))

        // assert
        @Expect("/elsewhere/src", sut.toString())
    }
}

@Test
class ConfigOutputDirTest {
    @TestCase
    func skipsTheRootPackageWhenDerivingTheOutputDir() {
        // act
        let sut = Config(srcDir: Path("/base/src"), outputPackage: "cjls.lsp_types")

        // assert
        @Expect("/base/src/lsp_types", sut.outputDir.toString())
    }

    @TestCase
    func mapsEveryDottedSegmentToADirectory() {
        // act
        let sut = Config(srcDir: Path("/base/src"), outputPackage: "cjls.lsp.types")

        // assert
        @Expect("/base/src/lsp/types", sut.outputDir.toString())
    }
}
