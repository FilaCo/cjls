package lsp_codegen

import std.collection.{ArrayList, HashSet}

extend String {
    func toAsciiUpperSnakeCase(): String {
        String.join(splitWords(this).map {w => w.toAsciiUpper()}, delimiter: "_")
    }

    func toAsciiLowerSnakeCase(): String {
        String.join(splitWords(this).map {w => w.toAsciiLower()}, delimiter: "_")
    }

    func toAsciiPascalCase(): String {
        String.join(splitWords(this).map {w => w.toAsciiTitle()})
    }
}

private func splitWords(name: String): Array<String> {
    let bytes = name.toArray()
    if (bytes.isEmpty()) {
        return []
    }

    let words = ArrayList<String>()
    var start = 0
    for (i in 1..bytes.size) {
        if (!bytes[i].isAsciiUpperCase()) {
            continue
        }
        // previous is not uppercase or (not last and next is lower case)
        let startsWord = !bytes[i - 1].isAsciiUpperCase() || (i + 1 < bytes.size && bytes[i + 1].isAsciiLowerCase())
        if (startsWord) {
            words.add(name[start..i])
            start = i
        }
    }
    words.add(name[start..])
    words.toArray()
}
