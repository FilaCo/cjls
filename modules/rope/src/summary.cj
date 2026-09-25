package rope

/**
 * What a column counts: bytes of UTF-8, UTF-16 code units, or characters (UTF-32 code units). The
 * three position encodings LSP knows.
 */
public enum Encoding <: Equatable<Encoding> & ToString {
    | Utf8
    | Utf16
    | Utf32

    public operator func ==(other: Encoding): Bool {
        match ((this, other)) {
            case (Utf8, Utf8) | (Utf16, Utf16) | (Utf32, Utf32) => true
            case _ => false
        }
    }

    public operator func !=(other: Encoding): Bool {
        !(this == other)
    }

    public func toString(): String {
        match (this) {
            case Utf8 => "utf-8"
            case Utf16 => "utf-16"
            case Utf32 => "utf-32"
        }
    }
}

/**
 * A place in a text by line and column, both from zero; what the column counts is the `Encoding`
 * it was made with.
 */
public struct LineColumn <: Equatable<LineColumn> & ToString {
    public LineColumn(public let line: Int64, public let column: Int64) {}

    public operator func ==(other: LineColumn): Bool {
        line == other.line && column == other.column
    }

    public operator func !=(other: LineColumn): Bool {
        !(this == other)
    }

    public func toString(): String {
        "${line}:${column}"
    }
}

/**
 * How long a text is by every measure a rope looks it up by. Only `\n` breaks a line, as in
 * rust-analyzer: a `\r` before it is the line's last character, and a lone `\r` breaks nothing.
 */
public struct TextSummary <: Equatable<TextSummary> & ToString {
    public TextSummary(
        public let bytes: Int64,
        public let utf16: Int64,
        public let chars: Int64,
        public let lineBreaks: Int64
    ) {}

    public static let EMPTY = TextSummary(0, 0, 0, 0)

    public static func of(text: String): TextSummary {
        summarize(text, 0, text.size)
    }

    /**
     * How long the text is in columns of `encoding`.
     */
    public func measure(encoding: Encoding): Int64 {
        match (encoding) {
            case Utf8 => bytes
            case Utf16 => utf16
            case Utf32 => chars
        }
    }

    public operator func +(other: TextSummary): TextSummary {
        TextSummary(bytes + other.bytes, utf16 + other.utf16, chars + other.chars, lineBreaks + other.lineBreaks)
    }

    public operator func ==(other: TextSummary): Bool {
        bytes == other.bytes && utf16 == other.utf16 && chars == other.chars && lineBreaks == other.lineBreaks
    }

    public operator func !=(other: TextSummary): Bool {
        !(this == other)
    }

    public func toString(): String {
        "TextSummary(bytes: ${bytes}, utf16: ${utf16}, chars: ${chars}, lineBreaks: ${lineBreaks})"
    }
}

/**
 * The summary of `text[from..to]`, which is valid UTF-8: every byte but a continuation one starts a
 * character, and one of four bytes is two UTF-16 units.
 */
func summarize(text: String, from: Int64, to: Int64): TextSummary {
    var utf16 = 0
    var chars = 0
    var lineBreaks = 0
    for (i in from..to) {
        let b = text[i]
        if (b == b'\n') {
            lineBreaks++
        }
        if (!isContinuation(b)) {
            chars++
            utf16 += if (b >= 0xF0) { 2 } else { 1 }
        }
    }
    TextSummary(to - from, utf16, chars, lineBreaks)
}

func isContinuation(b: Byte): Bool {
    (b & 0xC0) == 0x80
}

/**
 * How many bytes the character `lead` starts takes.
 */
func charWidth(lead: Byte): Int64 {
    if (lead < 0x80) {
        1
    } else if (lead >= 0xF0) {
        4
    } else if (lead >= 0xE0) {
        3
    } else if (lead >= 0xC0) {
        2
    } else {
        1
    }
}

/**
 * How many columns of `encoding` the character `lead` starts takes.
 */
func charUnits(lead: Byte, encoding: Encoding): Int64 {
    match (encoding) {
        case Utf8 => charWidth(lead)
        case Utf16 => if (lead >= 0xF0) { 2 } else { 1 }
        case Utf32 => 1
    }
}
