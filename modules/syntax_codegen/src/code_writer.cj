package syntax_codegen

import std.collection.*

let LINE_WIDTH = 120

/**
 * Builds a Cangjie file formatted as `cjfmt` would leave it, so what is checked in is exactly what is generated.
 */
class CodeWriter <: ToString {
    let sb = StringBuilder()
    var indentation = 0

    func line(text: String): Unit {
        if (!text.isEmpty()) {
            sb.append(" " * (indentation * 4))
            sb.append(text)
        }
        sb.append("\n")
    }

    func blank(): Unit {
        sb.append("\n")
    }

    /**
     * `head {`, the body one level in, `}`.
     */
    func block(head: String, body: () -> Unit): Unit {
        line("${head} {")
        indented(body)
        line("}")
    }

    func indented(body: () -> Unit): Unit {
        indentation++
        body()
        indentation--
    }

    /**
     * A doc comment of `lines`; nothing if there are none.
     */
    func doc(lines: Array<String>): Unit {
        if (lines.isEmpty()) {
            return
        }
        line("/**")
        for (l in lines) {
            if (l.isEmpty()) {
                line(" *")
            } else {
                line(" * ${l}")
            }
        }
        line(" */")
    }

    /**
     * `items` separated by `separator`, as many to a line as fit: `head` first, `tail` last, lines after the
     * first one level further in. A `leading` separator starts the next line, as `cjfmt` has the `|` of patterns.
     */
    func wrapped(head: String, items: Array<String>, separator: String, tail: String, leading!: Bool = false): Unit {
        let pieces = Array<String>(items.size) {
            i =>
            let item = if (leading && i > 0) {
                "${separator.trimAscii()} ${items[i]}"
            } else {
                items[i]
            }
            if (i + 1 == items.size) {
                "${item}${tail}"
            } else if (leading) {
                item
            } else {
                "${item}${separator}"
            }
        }
        let indent = indentation * 4
        var current = "${head}${pieces[0]}"
        var first = true
        for (i in 1..pieces.size) {
            let width = if (first) {
                indent
            } else {
                indent + 4
            }
            if (width + current.size + 1 + pieces[i].size <= LINE_WIDTH) {
                current = "${current} ${pieces[i]}"
            } else {
                emitWrappedLine(current, first)
                first = false
                current = pieces[i]
            }
        }
        emitWrappedLine(current, first)
    }

    private func emitWrappedLine(text: String, first: Bool): Unit {
        if (first) {
            line(text)
        } else {
            indented {=> line(text)}
        }
    }

    public func toString(): String {
        sb.toString()
    }
}

/**
 * `s` as a Cangjie string literal.
 */
func quoted(s: String): String {
    let sb = StringBuilder("\"")
    for (r in s.runes()) {
        match (r) {
            case '"' => sb.append("\\\"")
            case '\\' => sb.append("\\\\")
            case '$' => sb.append("\\$")
            case '\n' => sb.append("\\n")
            case _ => sb.append(r)
        }
    }
    sb.append("\"")
    sb.toString()
}

/**
 * `BinExpr` as `BIN_EXPR`.
 */
func screamingSnake(name: String): String {
    let sb = StringBuilder()
    let bytes = name.toArray()
    for (i in 0..bytes.size) {
        let b = bytes[i]
        let upper = b >= b'A' && b <= b'Z'
        if (upper && i > 0 && !(bytes[i - 1] >= b'A' && bytes[i - 1] <= b'Z')) {
            sb.append("_")
        }
        if (b >= b'a' && b <= b'z') {
            sb.append(Rune(UInt32(b - 32)))
        } else {
            sb.append(Rune(UInt32(b)))
        }
    }
    sb.toString()
}
