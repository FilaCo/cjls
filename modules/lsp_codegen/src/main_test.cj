package lsp_codegen

import std.argopt.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class ParseArgsTest {
    @TestCase[args in [["metaModel.json", "-c", "lsp_codegen.toml"], ["--config", "lsp_codegen.toml", "metaModel.json"],
        ["  metaModel.json  ", "-c", "  lsp_codegen.toml  "]]]
    func takesTheConfigFromAnOptionAndTheMetaModelFromTheRest(args: Array<String>) {
        // act
        let sut = parseArgs(args)

        // assert
        @Expect("lsp_codegen.toml", sut.configPath.toString())
        @Expect("metaModel.json", sut.metaModelPath.toString())
    }

    @TestCase[args in [["metaModel.json"], ["-c", "lsp_codegen.toml"], ["metaModel.json", "-c", "   "],
        ["   ", "-c", "lsp_codegen.toml"]]]
    func aMissingOrBlankPathIsRefused(args: Array<String>) {
        // act & assert
        @AssertThrows[ArgumentParseException](parseArgs(args))
    }
}
