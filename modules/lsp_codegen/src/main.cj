package lsp_codegen

import std.argopt.*
import std.fs.*
import stdx.serialization.serialization.*
import stdx.encoding.json.*

main(args: Array<String>): Int64 {
    let argSpec = [
        Long("src-dir", RequiredValue),
        Long("output-package", RequiredValue)
    ]

    let cfg = try {
        let parsed = parseArguments(
            args,
            argSpec
        )

        let metaModelPath = parsed.getRequiredValue(parsed.nonOptions.first, "metaModel file path")

        Config(metaModelPath: metaModelPath, srcDir: parsed.getRequiredOption("src-dir"),
            outputPackage: parsed.getRequiredOption("output-package"))
    } catch (e: ArgumentParseException) {
        eprintln("error: invalid arguments\nCause: ${e.message}")
        return 1
    }

    let metaModel = MetaModel.deserialize(
        DataModel.fromJson(JsonValue.fromStr(String.fromUtf8(File.readFrom(cfg.metaModelPath)))))

    return 0
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
