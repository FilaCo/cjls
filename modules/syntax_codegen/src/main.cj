package syntax_codegen

import std.fs.*

/**
 * `syntax_codegen <kinds file>`: writes the kinds and the typed views the kinds file and its grammar make.
 */
main(args: Array<String>): Int64 {
    if (args.size != 1) {
        eprintln("usage: syntax_codegen <kinds file>")
        return 2
    }
    try {
        let generated = generate(Path(args[0]))
        for (file in generated.files) {
            writeFormatted(file.path, file.contents)
            println("info: wrote ${file.path}")
        }
        for (n in generated.model.nodes where !n.handWritten.isEmpty()) {
            println("note: ${n.name} has accessors to write by hand: ${String.join(n.handWritten, delimiter: ", ")}")
        }
        0
    } catch (e: Exception) {
        eprintln("error: ${e.message}")
        1
    }
}
