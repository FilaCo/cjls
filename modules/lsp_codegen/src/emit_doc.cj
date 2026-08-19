package lsp_codegen

import std.collection.ArrayList

extend CjEmitter {
    func emitDoc(doc: DocIr): Unit {
        let lines = collectLines(doc)
        if (lines.isEmpty()) {
            return
        }

        blockComment(BlockComment(lines: lines))
    }
}

private func collectLines(doc: DocIr): Array<String> {
    let lines = ArrayList<String>()
    let documentation = doc.documentation ?? ""

    if (!documentation.isEmpty()) {
        for (line in documentation.split("\n")) {
            lines.add(line.trimAsciiEnd())
        }
    }

    // The metaModel records `@since` both in its own field and, for most types, inline at the end of
    // `documentation`. Emitting the field unconditionally would print half of them twice.
    let tags = ArrayList<String>()
    match (doc.sinceTags) {
        case Some(all) where all.size > 1 => for (tag in all) {
            tags.add("@since ${tag}")
        }
        case _ =>
            if (let Some(since) <- doc.since) {
                tags.add("@since ${since}")
            }
    }
    if (let Some(message) <- doc.deprecated) {
        tags.add("@deprecated ${message}")
    }
    if (doc.proposed) {
        tags.add("@proposed")
    }

    for (tag in tags) {
        if (documentation.contains(tag)) {
            continue
        }
        if (!lines.isEmpty()) {
            lines.add("")
        }
        lines.add(tag)
    }

    lines.toArray()
}
