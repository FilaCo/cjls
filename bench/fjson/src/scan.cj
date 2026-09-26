package fjson

/*
 * Finding the next byte a JSON string cannot hold as is, eight bytes at a time. Loads are
 * unaligned little-endian `UInt64`s, which every target cjls ships for (arm64, x86-64) allows.
 * A word goes by whole when none of its bytes is `"`, `\`, below 0x20 or, for the reader, above
 * 0x7F; the exact byte is then found one at a time. `hasZero` may also flag bytes above the first
 * real hit (the borrow), never below it, so the first flagged byte is always a real one.
 */

const QUOTE: Byte = 0x22
const BACKSLASH: Byte = 0x5C

const ONES: UInt64 = 0x0101010101010101
const HIGHS: UInt64 = 0x8080808080808080
const QUOTES: UInt64 = 0x2222222222222222
const BACKSLASHES: UInt64 = 0x5C5C5C5C5C5C5C5C
const SPACES: UInt64 = 0x2020202020202020

@OverflowWrapping
func special(x: UInt64): UInt64 {
    let q = x ^ QUOTES
    let s = x ^ BACKSLASHES
    ((q - ONES) & !q) | ((s - ONES) & !s) | ((x - SPACES) & !x)
}

/** The first index from `from` whose byte is `"`, `\`, a control character or not ASCII. */
func scanAscii(bytes: Array<Byte>, from: Int64): Int64 {
    let n = bytes.size
    var i = from
    unsafe {
        let handle = acquireArrayRawData(bytes)
        let p = handle.pointer
        while (i + 8 <= n) {
            let x = CPointer<UInt64>(p + i).read()
            if (((special(x) | x) & HIGHS) != 0) {
                break
            }
            i += 8
        }
        releaseArrayRawData(handle)
    }
    while (i < n) {
        let b = bytes[i]
        if (b == QUOTE || b == BACKSLASH || b < 0x20 || b >= 0x80) {
            return i
        }
        i++
    }
    n
}

/** The first index from `from` whose byte is `"`, `\` or a control character: what the writer escapes. */
func scanEscapes(bytes: Array<Byte>, from: Int64): Int64 {
    let n = bytes.size
    var i = from
    unsafe {
        let handle = acquireArrayRawData(bytes)
        let p = handle.pointer
        while (i + 8 <= n) {
            let x = CPointer<UInt64>(p + i).read()
            if ((special(x) & HIGHS) != 0) {
                break
            }
            i += 8
        }
        releaseArrayRawData(handle)
    }
    while (i < n) {
        let b = bytes[i]
        if (b == QUOTE || b == BACKSLASH || b < 0x20) {
            return i
        }
        i++
    }
    n
}

/** `scanAscii` a byte at a time: what SWAR is measured against. */
func scanAsciiScalar(bytes: Array<Byte>, from: Int64): Int64 {
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

/** `scanEscapes` a byte at a time. */
func scanEscapesScalar(bytes: Array<Byte>, from: Int64): Int64 {
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
