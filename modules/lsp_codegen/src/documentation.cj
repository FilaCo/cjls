package lsp_codegen

import std.collection.ArrayList

struct DocIr {
    DocIr(
        let documentation!: ?String = None,
        let since!: ?String = None,
        let sinceTags!: ?Array<String> = None,
        let proposed!: Bool = false,
        let deprecated!: ?String = None
    ) {}
}

func resolveDoc(enumeration: Enumeration): DocIr {
    docOf(
        documentation: enumeration.documentation,
        since: enumeration.since,
        sinceTags: enumeration.sinceTags,
        proposed: enumeration.proposed,
        deprecated: enumeration.deprecated
    )
}

func resolveDoc(entry: EnumerationEntry): DocIr {
    docOf(
        documentation: entry.documentation,
        since: entry.since,
        sinceTags: entry.sinceTags,
        proposed: entry.proposed,
        deprecated: entry.deprecated
    )
}

private func docOf(documentation!: ?String, since!: ?String, sinceTags!: ?Array<String>, proposed!: ?Bool,
    deprecated!: ?String) {
    DocIr(documentation: documentation, since: since, sinceTags: sinceTags, proposed: proposed ?? false,
        deprecated: deprecated)
}

extend CjEmitter {
    func emitDoc(doc: DocIr): Unit {
        let lines = collectLines(doc)
        if (lines.isEmpty()) {
            return
        }

        emitln(DocComment(lines: lines))
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
