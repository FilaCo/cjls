package lsp_codegen

import std.argopt.*
import std.fs.*
import std.process.*
import stdx.serialization.serialization.*
import stdx.encoding.json.*
import cjtoml.*

main(args: Array<String>): Int64 {
    try {
        mainImpl(args)
    } catch (e: Exception) {
        eprintln("error: ${e.message}")
        return 1
    }
}

private func mainImpl(args: Array<String>): Int64 {
    let (cfg, metaModelPath) = parseArgs(args)
    let metaModel = MetaModel.deserialize(
        DataModel.fromJson(JsonValue.fromStr(String.fromUtf8(File.readFrom(metaModelPath)))))

    let cjFiles = generateCjFiles(cfg, metaModel)
    if (!exists(cfg.outputDir)) {
        Directory.create(cfg.outputDir, recursive: true)
    }
    for (file in cjFiles) {
        File.writeTo(file.path, file.contents.toArray())
    }
    let exitCode = execute("cjfmt", ["-d", cfg.outputDir.toString()])
    if (exitCode != 0) {
        eprintln("cjfmt run failed!")
    }
    println("info: generated ${cjFiles.size} Cangjie files")

    exitCode
}

private func parseArgs(args: Array<String>): (Config, /* metaModelPath */ Path) {
    let parsed = parseArguments(
        args,
        [
            Full("config", r'c', RequiredValue),
        ]
    )

    let metaModelPath = Path(parsed.getRequiredValue(parsed.nonOptions.first, "metaModel file path"))
    
    let cfgPath = parsed.getRequiredOption("config")
    let cfg = unmarshal<Config>(cfgPath)

    (cfg, metaModelPath)
}

extend ParsedArguments {
    /**
     * @throws ArgumentParseException - if option is missing or its value is an empty string
     */
    func getRequiredOption(key: String, trim!: Bool = true): String {
        getRequiredValue(options.get(key), "`${key}` option", trim: trim)
    }
    /**
     * @throws ArgumentParseException - if v is `None` or its value is an empty string
     */
    func getRequiredValue(v: ?String, what: String, trim!: Bool = true): String {
        v.map {
            it => if (trim) {
                it.trimAscii()
            } else {
                it
            }
        }.filter {it => !it.isEmpty()}.getOrThrow {=> ArgumentParseException("missing required `${what}`")}
    }
}
