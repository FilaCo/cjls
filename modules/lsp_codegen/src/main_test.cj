package lsp_codegen

import std.argopt.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class ParseArgsTest {
    @TestCase
    func takesTheConfigFromAnOptionAndTheMetaModelFromTheRest() {
        // arrange
        let args = ["metaModel.json", "-c", "lsp_codegen.toml"]

        // act
        let sut = parseArgs(args)

        // assert
        @Expect("lsp_codegen.toml", sut.configPath.toString())
        @Expect("metaModel.json", sut.metaModelPath.toString())
    }

    @TestCase
    func acceptsTheLongFormOfTheConfigOption() {
        // arrange
        let args = ["--config", "lsp_codegen.toml", "metaModel.json"]

        // act
        let sut = parseArgs(args)

        // assert
        @Expect("lsp_codegen.toml", sut.configPath.toString())
        @Expect("metaModel.json", sut.metaModelPath.toString())
    }

    @TestCase
    func trimsSurroundingWhitespaceFromBothPaths() {
        // arrange
        let args = ["  metaModel.json  ", "-c", "  lsp_codegen.toml  "]

        // act
        let sut = parseArgs(args)

        // assert
        @Expect("lsp_codegen.toml", sut.configPath.toString())
        @Expect("metaModel.json", sut.metaModelPath.toString())
    }

    @TestCase
    func aMissingConfigOptionThrows() {
        // arrange
        let args = ["metaModel.json"]

        // act & assert
        @AssertThrows[ArgumentParseException](parseArgs(args))
    }

    @TestCase
    func aMissingMetaModelPathThrows() {
        // arrange
        let args = ["-c", "lsp_codegen.toml"]

        // act
        let e = @AssertThrows[ArgumentParseException](parseArgs(args))

        // assert
        @Expect("missing required metaModel file path", e.message)
    }

    /**
     * A blank value is rejected rather than turned into `Path("")`, which throws on every join.
     */
    @TestCase
    func aBlankConfigValueThrows() {
        // arrange
        let args = ["metaModel.json", "-c", "   "]

        // act & assert
        @AssertThrows[ArgumentParseException](parseArgs(args))
    }

    @TestCase
    func aBlankMetaModelPathThrows() {
        // arrange
        let args = ["   ", "-c", "lsp_codegen.toml"]

        // act & assert
        @AssertThrows[ArgumentParseException](parseArgs(args))
    }
}
