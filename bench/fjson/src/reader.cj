package fjson

import std.convert.*

public class FjException <: Exception {
    public init(message: String) {
        super(message)
    }
}

public enum FjKind {
    | Object | Array | Str | Number | Boolean | Null
}

const MAX_DEPTH = 512

/**
 * A pull reader over the bytes of one JSON text, no tree and no copy of it: keys are compared
 * where they lie, a string without escapes is one copy into its `String`, UTF-8 is checked on the
 * way, and `rawValue` is a slice of the input. What a generated decoder calls:
 *
 *     r.beginObject()
 *     while (r.nextKey()) {
 *         if (r.keyIs("uri")) { uri = r.readString() } else { r.skipValue() }
 *     }
 *
 * `swar: false` scans strings a byte at a time, for the benchmark.
 */
public class FjReader {
    private var pos = 0
    // whether the container just opened has had no member yet
    private var first = false
    private var keyStart = 0
    private var keyLength = 0
    private var keyInScratch = false
    // unescaped strings are built here and copied out, one buffer for the reader's lifetime
    private var scratch = Array<Byte>(256, repeat: 0)

    public FjReader(private var bytes: Array<Byte>, private let swar!: Bool = false) {}

    /** The reader at the start of other bytes, keeping its buffer: one reader for a connection's read loop. */
    @Frozen
    public func reset(next: Array<Byte>): Unit {
        bytes = next
        pos = 0
        first = false
    }

    public prop position: Int64 {
        get() {
            pos
        }
    }

    private func fail(message: String): FjException {
        FjException("${message} at byte ${pos}")
    }

    private func ws(): Unit {
        while (pos < bytes.size) {
            let b = bytes[pos]
            if (b == 0x20 || b == 0x0A || b == 0x0D || b == 0x09) {
                pos++
            } else {
                return
            }
        }
    }

    private func peekByte(): Byte {
        ws()
        if (pos >= bytes.size) {
            throw fail("unexpected end of input")
        }
        bytes[pos]
    }

    private func expect(b: Byte, what: String): Unit {
        if (peekByte() != b) {
            throw fail("expected ${what}")
        }
        pos++
    }

    private func scan(from: Int64): Int64 {
        if (swar) {
            scanAscii(bytes, from)
        } else {
            scanAsciiScalar(bytes, from)
        }
    }

    /** Past the plain part of a string from `from`: ASCII without escapes and valid UTF-8. */
    private func scanPlain(from: Int64): Int64 {
        var i = scan(from)
        while (i < bytes.size && bytes[i] >= 0x80) {
            let length = utf8Length(bytes, i)
            if (length == 0) {
                pos = i
                throw fail("invalid UTF-8")
            }
            i = scan(i + length)
        }
        i
    }

    @Frozen
    public func peekKind(): FjKind {
        match (peekByte()) {
            case 0x7B => FjKind.Object
            case 0x5B => FjKind.Array
            case 0x22 => FjKind.Str
            case 0x74 | 0x66 => FjKind.Boolean
            case 0x6E => FjKind.Null
            case b where b == 0x2D || (b >= 0x30 && b <= 0x39) => FjKind.Number
            case _ => throw fail("expected a value")
        }
    }

    @Frozen
    public func beginObject(): Unit {
        expect(0x7B, "`{`")
        first = true
    }

    /** The next member's key, or `false` past the closing `}`. The key is then `keyIs`'s. */
    @Frozen
    public func nextKey(): Bool {
        let b = peekByte()
        if (b == 0x7D) {
            pos++
            first = false
            return false
        }
        if (!first) {
            if (b != 0x2C) {
                throw fail("expected `,` or `}`")
            }
            pos++
        }
        first = false
        expect(QUOTE, "a key")
        let start = pos
        let end = scanPlain(start)
        if (end < bytes.size && bytes[end] == QUOTE) {
            keyStart = start
            keyLength = end - start
            keyInScratch = false
            pos = end + 1
        } else {
            keyStart = 0
            keyLength = unescape(start, end)
            keyInScratch = true
        }
        expect(0x3A, "`:`")
        true
    }

    @Frozen
    public func keyIs(name: String): Bool {
        if (name.size != keyLength) {
            return false
        }
        let source = if (keyInScratch) { scratch } else { bytes }
        for (i in 0..keyLength) {
            if (source[keyStart + i] != name[i]) {
                return false
            }
        }
        true
    }

    @Frozen
    public func key(): String {
        let source = if (keyInScratch) { scratch } else { bytes }
        unsafe { String.fromUtf8Unchecked(source[keyStart..keyStart + keyLength]) }
    }

    @Frozen
    public func beginArray(): Unit {
        expect(0x5B, "`[`")
        first = true
    }

    /** Whether another item follows, or `false` past the closing `]`. */
    @Frozen
    public func nextItem(): Bool {
        let b = peekByte()
        if (b == 0x5D) {
            pos++
            first = false
            return false
        }
        if (!first) {
            if (b != 0x2C) {
                throw fail("expected `,` or `]`")
            }
            pos++
        }
        first = false
        true
    }

    @Frozen
    public func readString(): String {
        expect(QUOTE, "a string")
        let start = pos
        let end = scanPlain(start)
        if (end < bytes.size && bytes[end] == QUOTE) {
            pos = end + 1
            return unsafe { String.fromUtf8Unchecked(bytes[start..end]) }
        }
        let length = unescape(start, end)
        unsafe { String.fromUtf8Unchecked(scratch[0..length]) }
    }

    private func reserve(length: Int64, extra: Int64): Unit {
        if (length + extra > scratch.size) {
            let grown = Array<Byte>(max(scratch.size * 2, length + extra), repeat: 0)
            scratch.copyTo(grown, 0, 0, length)
            scratch = grown
        }
    }

    private func push(length: Int64, b: Byte): Int64 {
        reserve(length, 1)
        scratch[length] = b
        length + 1
    }

    /**
     * The string from `start`, whose plain part ends at `end`, unescaped into `scratch`; its
     * length there. `pos` ends past the closing quote.
     */
    private func unescape(start: Int64, end: Int64): Int64 {
        var length = end - start
        reserve(0, length)
        bytes.copyTo(scratch, start, 0, length)
        var i = end
        while (true) {
            if (i >= bytes.size) {
                pos = i
                throw fail("unterminated string")
            }
            let b = bytes[i]
            if (b == QUOTE) {
                pos = i + 1
                return length
            }
            if (b < 0x20) {
                pos = i
                throw fail("control character in a string")
            }
            // a backslash
            if (i + 1 >= bytes.size) {
                pos = i
                throw fail("unterminated string")
            }
            let e = bytes[i + 1]
            i += 2
            match (e) {
                case 0x22 | 0x5C | 0x2F => length = push(length, e)
                case 0x62 => length = push(length, 0x08)
                case 0x66 => length = push(length, 0x0C)
                case 0x6E => length = push(length, 0x0A)
                case 0x72 => length = push(length, 0x0D)
                case 0x74 => length = push(length, 0x09)
                case 0x75 =>
                    var cp = hex4(i)
                    i += 4
                    if (cp >= 0xD800 && cp <= 0xDBFF) {
                        if (i + 6 > bytes.size || bytes[i] != BACKSLASH || bytes[i + 1] != 0x75) {
                            pos = i
                            throw fail("a lone surrogate")
                        }
                        let low = hex4(i + 2)
                        if (low < 0xDC00 || low > 0xDFFF) {
                            pos = i
                            throw fail("a lone surrogate")
                        }
                        cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00)
                        i += 6
                    } else if (cp >= 0xDC00 && cp <= 0xDFFF) {
                        pos = i
                        throw fail("a lone surrogate")
                    }
                    length = pushUtf8(length, cp)
                case _ =>
                    pos = i - 1
                    throw fail("invalid escape")
            }
            let runEnd = scanPlain(i)
            reserve(length, runEnd - i)
            bytes.copyTo(scratch, i, length, runEnd - i)
            length += runEnd - i
            i = runEnd
        }
        0
    }

    private func hex4(at: Int64): UInt32 {
        if (at + 4 > bytes.size) {
            pos = at
            throw fail("unterminated escape")
        }
        var v: UInt32 = 0
        for (k in 0..4) {
            let c = bytes[at + k]
            let d: UInt32 = if (c >= 0x30 && c <= 0x39) {
                UInt32(c - 0x30)
            } else if (c >= 0x61 && c <= 0x66) {
                UInt32(c - 0x61 + 10)
            } else if (c >= 0x41 && c <= 0x46) {
                UInt32(c - 0x41 + 10)
            } else {
                pos = at + k
                throw fail("invalid hex digit")
            }
            v = v * 16 + d
        }
        v
    }

    private func pushUtf8(length: Int64, cp: UInt32): Int64 {
        reserve(length, 4)
        if (cp < 0x80) {
            scratch[length] = UInt8(cp)
            return length + 1
        }
        if (cp < 0x800) {
            scratch[length] = UInt8(0xC0 | (cp >> 6))
            scratch[length + 1] = UInt8(0x80 | (cp & 0x3F))
            return length + 2
        }
        if (cp < 0x10000) {
            scratch[length] = UInt8(0xE0 | (cp >> 12))
            scratch[length + 1] = UInt8(0x80 | ((cp >> 6) & 0x3F))
            scratch[length + 2] = UInt8(0x80 | (cp & 0x3F))
            return length + 3
        }
        scratch[length] = UInt8(0xF0 | (cp >> 18))
        scratch[length + 1] = UInt8(0x80 | ((cp >> 12) & 0x3F))
        scratch[length + 2] = UInt8(0x80 | ((cp >> 6) & 0x3F))
        scratch[length + 3] = UInt8(0x80 | (cp & 0x3F))
        length + 4
    }

    /** An integer, `-` and digits: what LSP's `integer` and `uinteger` are. */
    @Frozen
    public func readInt64(): Int64 {
        var negative = false
        if (peekByte() == 0x2D) {
            negative = true
            pos++
        }
        let start = pos
        // accumulated negative, so that Int64.Min fits
        var v: Int64 = 0
        while (pos < bytes.size && bytes[pos] >= 0x30 && bytes[pos] <= 0x39) {
            let d = Int64(bytes[pos] - 0x30)
            if (v < (Int64.Min + d) / 10) {
                throw fail("integer out of range")
            }
            v = v * 10 - d
            pos++
        }
        let digits = pos - start
        if (digits == 0 || (digits > 1 && bytes[start] == 0x30)) {
            throw fail("expected an integer")
        }
        if (pos < bytes.size && (bytes[pos] == 0x2E || bytes[pos] == 0x65 || bytes[pos] == 0x45)) {
            throw fail("expected an integer, not a decimal")
        }
        if (negative) {
            v
        } else if (v == Int64.Min) {
            throw fail("integer out of range")
        } else {
            -v
        }
    }

    @Frozen
    public func readInt32(): Int32 {
        let v = readInt64()
        if (v < Int64(Int32.Min) || v > Int64(Int32.Max)) {
            throw fail("integer out of range")
        }
        Int32(v)
    }

    @Frozen
    public func readUInt32(): UInt32 {
        let v = readInt64()
        if (v < 0 || v > Int64(UInt32.Max)) {
            throw fail("integer out of range")
        }
        UInt32(v)
    }

    @Frozen
    public func readFloat64(): Float64 {
        let start = pos
        skipNumber()
        Float64.parse(unsafe { String.fromUtf8Unchecked(bytes[start..pos]) })
    }

    @Frozen
    public func readBool(): Bool {
        match (peekByte()) {
            case 0x74 =>
                literal("true")
                true
            case 0x66 =>
                literal("false")
                false
            case _ => throw fail("expected a boolean")
        }
    }

    @Frozen
    public func peekNull(): Bool {
        peekByte() == 0x6E
    }

    @Frozen
    public func readNull(): Unit {
        ws()
        literal("null")
    }

    private func literal(text: String): Unit {
        if (pos + text.size > bytes.size) {
            throw fail("expected `${text}`")
        }
        for (i in 0..text.size) {
            if (bytes[pos + i] != text[i]) {
                throw fail("expected `${text}`")
            }
        }
        pos += text.size
    }

    private func skipNumber(): Unit {
        ws()
        let start = pos
        if (pos < bytes.size && bytes[pos] == 0x2D) {
            pos++
        }
        let digitsStart = pos
        while (pos < bytes.size && bytes[pos] >= 0x30 && bytes[pos] <= 0x39) {
            pos++
        }
        if (pos == digitsStart || (pos - digitsStart > 1 && bytes[digitsStart] == 0x30)) {
            pos = start
            throw fail("expected a number")
        }
        if (pos < bytes.size && bytes[pos] == 0x2E) {
            pos++
            let fraction = pos
            while (pos < bytes.size && bytes[pos] >= 0x30 && bytes[pos] <= 0x39) {
                pos++
            }
            if (pos == fraction) {
                throw fail("expected a digit")
            }
        }
        if (pos < bytes.size && (bytes[pos] == 0x65 || bytes[pos] == 0x45)) {
            pos++
            if (pos < bytes.size && (bytes[pos] == 0x2B || bytes[pos] == 0x2D)) {
                pos++
            }
            let exponent = pos
            while (pos < bytes.size && bytes[pos] >= 0x30 && bytes[pos] <= 0x39) {
                pos++
            }
            if (pos == exponent) {
                throw fail("expected a digit")
            }
        }
    }

    private func skipString(): Unit {
        expect(QUOTE, "a string")
        var i = pos
        while (true) {
            i = scanPlain(i)
            if (i >= bytes.size) {
                pos = i
                throw fail("unterminated string")
            }
            match (bytes[i]) {
                case 0x22 =>
                    pos = i + 1
                    return
                case 0x5C => i += 2
                case _ =>
                    pos = i
                    throw fail("control character in a string")
            }
        }
    }

    @Frozen
    public func skipValue(): Unit {
        skipValue(0)
    }

    private func skipValue(depth: Int64): Unit {
        if (depth > MAX_DEPTH) {
            throw fail("nested too deep")
        }
        match (peekKind()) {
            case FjKind.Object =>
                beginObject()
                while (nextKey()) {
                    skipValue(depth + 1)
                }
            case FjKind.Array =>
                beginArray()
                while (nextItem()) {
                    skipValue(depth + 1)
                }
            case FjKind.Str => skipString()
            case FjKind.Number => skipNumber()
            case FjKind.Boolean => readBool()
            case FjKind.Null => readNull()
        }
        // a value was read: whatever container holds it has a member now
        first = false
    }

    /** The next value's own bytes, a slice of the input: `params` read before `method` is known. */
    @Frozen
    public func rawValue(): Array<Byte> {
        ws()
        let start = pos
        skipValue()
        bytes[start..pos]
    }

    /** Nothing but whitespace is left. */
    @Frozen
    public func end(): Unit {
        ws()
        if (pos != bytes.size) {
            throw fail("trailing characters")
        }
    }
}
