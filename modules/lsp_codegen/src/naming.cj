package lsp_codegen

import std.collection.{ArrayList, HashSet}

/**
 * Cangjie's reserved words.
 */
private let CANGJIE_KEYWORDS = HashSet<String>(
    [
        "Bool",
        "Float16",
        "Float32",
        "Float64",
        "Int8",
        "Int16",
        "Int32",
        "Int64",
        "IntNative",
        "Nothing",
        "Rune",
        "This",
        "UInt8",
        "UInt16",
        "UInt32",
        "UInt64",
        "UIntNative",
        "Unit",
        "VArray",
        "abstract",
        "as",
        "break",
        "case",
        "catch",
        "class",
        "const",
        "continue",
        "do",
        "else",
        "enum",
        "extend",
        "false",
        "finally",
        "for",
        "foreign",
        "func",
        "if",
        "import",
        "in",
        "init",
        "inout",
        "interface",
        "is",
        "let",
        "macro",
        "main",
        "match",
        "mut",
        "open",
        "operator",
        "override",
        "package",
        "private",
        "prop",
        "protected",
        "public",
        "quote",
        "redef",
        "return",
        "sealed",
        "spawn",
        "static",
        "struct",
        "super",
        "synchronized",
        "this",
        "throw",
        "true",
        "try",
        "type",
        "unsafe",
        "var",
        "where",
        "while"
    ]
)

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

    func toRawIdentIfNecessary(): String {
        if (CANGJIE_KEYWORDS.contains(this)) {
            "`${this}`"
        } else {
            this
        }
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
