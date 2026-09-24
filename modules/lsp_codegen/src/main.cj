package lsp_codegen

import std.argopt.*
import std.fs.*
import std.process.*
import stdx.serialization.serialization.*
import stdx.encoding.json.*

main(args: Array<String>): Int64 {
    try {
        mainImpl(args)
    } catch (e: Exception) {
        eprintln("error: ${e.message}")
        return 1
    }
}

private func mainImpl(args: Array<String>): Int64 {
    let cliArgs = parseArgs(args)
    let cfg = Config.load(cliArgs.configPath)
    let metaModel = MetaModel.deserialize(
        DataModel.fromJson(JsonValue.fromStr(String.fromUtf8(File.readFrom(cliArgs.metaModelPath)))))

    let cjFiles = generateCjFiles(cfg, metaModel)
    if (!exists(cfg.outputDir)) {
        Directory.create(cfg.outputDir, recursive: true)
    }
    for (file in cjFiles) {
        File.writeTo(file.path, file.contents.toArray())
    }
    let exitCode = execute("cjfmt", ["-d", cfg.outputDir.toString()], stdOut: Discard)
    if (exitCode != 0) {
        eprintln("cjfmt run failed!")
    }
    println("info: generated ${cjFiles.size} Cangjie files")

    exitCode
}

struct CliArgs {
    CliArgs(let configPath!: Path, let metaModelPath!: Path) {}
}

func parseArgs(args: Array<String>): CliArgs {
    let parsed = parseArguments(
        args,
        [Full("config", r'c', RequiredValue)]
    )

    CliArgs(
        configPath: Path(parsed.getRequiredOption("config")),
        metaModelPath: Path(parsed.getRequiredValue(parsed.nonOptions.first, "metaModel file path"))
    )
}

extend ParsedArguments {
    /**
     * @throws ArgumentParseException - if the option is missing or blank
     */
    func getRequiredOption(key: String): String {
        getRequiredValue(options.get(key), "`${key}` option")
    }

    /**
     * A blank value is refused rather than turned into `Path("")`, which throws on every join.
     *
     * @throws ArgumentParseException - if `v` is `None` or blank
     */
    func getRequiredValue(v: ?String, what: String): String {
        v.map {it => it.trimAscii()}.filter {it => !it.isEmpty()}.getOrThrow {
            => ArgumentParseException("missing required ${what}")
        }
    }
}
