package lsp_codegen

import std.fs.Path

struct Config {
    let outputDir: Path

    Config(let srcDir!: Path, let outputPackage!: String) {
        var outputDirVal = srcDir
        // skip root package name
        for (s in outputPackage.split(".")[1..]) {
            outputDirVal = outputDirVal.join(s)
        }
        outputDir = outputDirVal
    }
}
