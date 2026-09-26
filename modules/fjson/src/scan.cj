package fjson

/*
 * Finding the next byte a JSON string cannot hold as is, one byte at a time. Eight at a time
 * (SWAR over `CPointer<UInt64>` loads) was measured slower: `acquireArrayRawData` costs ~100 ns a
 * call, and LSP text has an escape (`\n`, `"`) every few dozen bytes (#9).
 */

const QUOTE: Byte = 0x22
const BACKSLASH: Byte = 0x5C

/** The first index from `from` whose byte is `"`, `\`, a control character or not ASCII: where the reader stops. */
func scanAscii(bytes: Array<Byte>, from: Int64): Int64 {
    var i = from
    while (i < bytes.size) {
        let b = bytes[i]
        if (b == QUOTE || b == BACKSLASH || b < 0x20 || b >= 0x80) {
            return i
        }
        i++
    }
    bytes.size
}

/** The first index from `from` whose byte is `"`, `\` or a control character: what the writer escapes. */
func scanEscapes(bytes: Array<Byte>, from: Int64): Int64 {
    var i = from
    while (i < bytes.size) {
        let b = bytes[i]
        if (b == QUOTE || b == BACKSLASH || b < 0x20) {
            return i
        }
        i++
    }
    bytes.size
}

/**
 * The length of the UTF-8 sequence starting at `i`, or 0 when it is not a valid one: overlong
 * forms, surrogates and code points past U+10FFFF included, as RFC 3629 has it.
 */
func utf8Length(bytes: Array<Byte>, i: Int64): Int64 {
    let n = bytes.size
    let b0 = bytes[i]
    func cont(at: Int64): Bool {
        at < n && (bytes[at] & 0xC0) == 0x80
    }
    if (b0 >= 0xC2 && b0 <= 0xDF) {
        return if (cont(i + 1)) { 2 } else { 0 }
    }
    if (b0 >= 0xE0 && b0 <= 0xEF) {
        if (i + 1 >= n) {
            return 0
        }
        let b1 = bytes[i + 1]
        let ok = match (b0) {
            case 0xE0 => b1 >= 0xA0 && b1 <= 0xBF
            case 0xED => b1 >= 0x80 && b1 <= 0x9F
            case _ => (b1 & 0xC0) == 0x80
        }
        return if (ok && cont(i + 2)) { 3 } else { 0 }
    }
    if (b0 >= 0xF0 && b0 <= 0xF4) {
        if (i + 1 >= n) {
            return 0
        }
        let b1 = bytes[i + 1]
        let ok = match (b0) {
            case 0xF0 => b1 >= 0x90 && b1 <= 0xBF
            case 0xF4 => b1 >= 0x80 && b1 <= 0x8F
            case _ => (b1 & 0xC0) == 0x80
        }
        return if (ok && cont(i + 2) && cont(i + 3)) { 4 } else { 0 }
    }
    0
}
