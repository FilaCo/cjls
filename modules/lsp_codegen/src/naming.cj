package lsp_codegen

import std.ast.*
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

private let RESERVED = HashSet<String>(
    [
        "as",
        "break",
        "case",
        "catch",
        "class",
        "common",
        "const",
        "continue",
        "do",
        "else",
        "enum",
        "extend",
        "false",
        "finally",
        "for",
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
        "operator",
        "package",
        "prop",
        "quote",
        "return",
        "spawn",
        "specific",
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
        "while",
        "Unit",
        "Int8",
        "Int16",
        "Int32",
        "Int64",
        "IntNative",
        "UInt8",
        "UInt16",
        "UInt32",
        "UInt64",
        "UIntNative",
        "Float16",
        "Float32",
        "Float64",
        "Rune",
        "Bool",
        "Nothing",
        "This",
        "VArray"
    ]
)

func escapedIdent(name: String): Token {
    if (RESERVED.contains(name)) {
        Token(IDENTIFIER, "`${name}`")
    } else {
        Token(IDENTIFIER, name)
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
