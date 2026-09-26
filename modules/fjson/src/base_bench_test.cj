package fjson

import std.collection.*
import std.convert.*
import std.unittest.*
import std.unittest.testmacro.*

/* GENERATED for the A/B of the perf experiments: fjson as of `feat/fjson`, renamed. Not for merging. */

/*
 * Finding the next byte a JSON string cannot hold as is, one byte at a time. Eight at a time
 * (SWAR over `CPointer<UInt64>` loads) was measured slower: `acquireArrayRawData` costs ~100 ns a
 * call, and LSP text has an escape (`\n`, `"`) every few dozen bytes (#9).
 */

const BASE_QUOTE: Byte = 0x22
const BASE_BACKSLASH: Byte = 0x5C

/** The first index from `from` whose byte is `"`, `\`, a control character or not ASCII: where the reader stops. */
func baseScanAscii(bytes: Array<Byte>, from: Int64): Int64 {
    var i = from
    while (i < bytes.size) {
        let b = bytes[i]
        if (b == BASE_QUOTE || b == BASE_BACKSLASH || b < 0x20 || b >= 0x80) {
            return i
        }
        i++
    }
    bytes.size
}

/** The first index from `from` whose byte is `"`, `\` or a control character: what the writer escapes. */
func baseScanEscapes(bytes: Array<Byte>, from: Int64): Int64 {
    var i = from
    while (i < bytes.size) {
        let b = bytes[i]
        if (b == BASE_QUOTE || b == BASE_BACKSLASH || b < 0x20) {
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
func baseUtf8Length(bytes: Array<Byte>, i: Int64): Int64 {
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




const BASE_MAX_DEPTH = 512

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
 * `reset` points it at the next message and keeps its buffer, so the read loop of a connection
 * needs one reader.
 */
public class BaseReader {
    private var pos = 0
    // whether the container just opened has had no member yet
    private var first = false
    private var keyStart = 0
    private var keyLength = 0
    private var keyInScratch = false
    // unescaped strings are built here and copied out, one buffer for the reader's lifetime
    private var scratch = Array<Byte>(256, repeat: 0)

    public BaseReader(private var bytes: Array<Byte>) {}

    /** The reader at the start of other bytes, keeping its buffer. */
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

    /** Past the plain part of a string from `from`: ASCII without escapes and valid UTF-8. */
    private func scanPlain(from: Int64): Int64 {
        var i = baseScanAscii(bytes, from)
        while (i < bytes.size && bytes[i] >= 0x80) {
            let length = baseUtf8Length(bytes, i)
            if (length == 0) {
                pos = i
                throw fail("invalid UTF-8")
            }
            i = baseScanAscii(bytes, i + length)
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
        expect(BASE_QUOTE, "a key")
        let start = pos
        let end = scanPlain(start)
        if (end < bytes.size && bytes[end] == BASE_QUOTE) {
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
        expect(BASE_QUOTE, "a string")
        let start = pos
        let end = scanPlain(start)
        if (end < bytes.size && bytes[end] == BASE_QUOTE) {
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
            if (b == BASE_QUOTE) {
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
                        if (i + 6 > bytes.size || bytes[i] != BASE_BACKSLASH || bytes[i + 1] != 0x75) {
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
        expect(BASE_QUOTE, "a string")
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
        if (depth > BASE_MAX_DEPTH) {
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

let BASE_HEX: Array<Byte> = [0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66]

/**
 * A JSON writer into one growing byte buffer: no tree, no `String` of the whole, numbers written
 * digit by digit in place, strings copied a run at a time between the bytes they escape. Commas
 * need no stack: every value is preceded by one unless a container or a key was just opened.
 * `bytes()` is a slice of the buffer, what the transport writes after its header; `clear` then
 * empties it for the next message, keeping the buffer.
 */
public class BaseWriter {
    private var buf: Array<Byte>
    private var length = 0
    private var needComma = false

    public init(capacity!: Int64 = 1024) {
        buf = Array<Byte>(capacity, repeat: 0)
    }

    public prop size: Int64 {
        get() {
            length
        }
    }

    @Frozen
    public func bytes(): Array<Byte> {
        buf[0..length]
    }

    /** Empty again, keeping the buffer: once `bytes()` has been written out, the next message reuses it. */
    @Frozen
    public func clear(): Unit {
        length = 0
        needComma = false
    }

    private func reserve(extra: Int64): Unit {
        if (length + extra > buf.size) {
            let grown = Array<Byte>(max(buf.size * 2, length + extra), repeat: 0)
            buf.copyTo(grown, 0, 0, length)
            buf = grown
        }
    }

    private func put(b: Byte): Unit {
        reserve(1)
        buf[length] = b
        length++
    }

    private func separate(): Unit {
        if (needComma) {
            put(0x2C)
        }
    }

    @Frozen
    public func beginObject(): Unit {
        separate()
        put(0x7B)
        needComma = false
    }

    @Frozen
    public func endObject(): Unit {
        put(0x7D)
        needComma = true
    }

    @Frozen
    public func beginArray(): Unit {
        separate()
        put(0x5B)
        needComma = false
    }

    @Frozen
    public func endArray(): Unit {
        put(0x5D)
        needComma = true
    }

    @Frozen
    public func name(key: String): Unit {
        separate()
        quoted(key)
        put(0x3A)
        needComma = false
    }

    @Frozen
    public func string(value: String): Unit {
        separate()
        quoted(value)
        needComma = true
    }

    @Frozen
    public func int64(value: Int64): Unit {
        separate()
        digits(value)
        needComma = true
    }

    @Frozen
    public func uint32(value: UInt32): Unit {
        int64(Int64(value))
    }

    @Frozen
    public func int32(value: Int32): Unit {
        int64(Int64(value))
    }

    @Frozen
    public func bool(value: Bool): Unit {
        separate()
        literal(if (value) { "true" } else { "false" })
        needComma = true
    }

    @Frozen
    public func null(): Unit {
        separate()
        literal("null")
        needComma = true
    }

    @Frozen
    public func float64(value: Float64): Unit {
        separate()
        literal(value.toString())
        needComma = true
    }

    /** A value already encoded, written as it is. */
    @Frozen
    public func raw(value: Array<Byte>): Unit {
        separate()
        reserve(value.size)
        value.copyTo(buf, 0, length, value.size)
        length += value.size
        needComma = true
    }

    private func literal(text: String): Unit {
        let source = unsafe { text.rawData() }
        reserve(source.size)
        source.copyTo(buf, 0, length, source.size)
        length += source.size
    }

    private func digits(value: Int64): Unit {
        reserve(20)
        var magnitude = if (value < 0) {
            buf[length] = 0x2D
            length++
            // Int64.Min has no positive Int64
            UInt64(-(value + 1)) + 1
        } else {
            UInt64(value)
        }
        var count = 1
        var probe = magnitude
        while (probe >= 10) {
            probe /= 10
            count++
        }
        var i = length + count - 1
        while (i >= length) {
            buf[i] = UInt8(magnitude % 10) + 0x30
            magnitude /= 10
            i--
        }
        length += count
    }

    private func quoted(value: String): Unit {
        let source = unsafe { value.rawData() }
        let n = source.size
        reserve(n + 2)
        buf[length] = BASE_QUOTE
        length++
        var i = 0
        while (i < n) {
            let runEnd = baseScanEscapes(source, i)
            if (runEnd > i) {
                reserve(runEnd - i + 1)
                source.copyTo(buf, i, length, runEnd - i)
                length += runEnd - i
            }
            if (runEnd >= n) {
                break
            }
            escape(source[runEnd])
            i = runEnd + 1
        }
        put(BASE_QUOTE)
    }

    private func escape(b: Byte): Unit {
        reserve(6)
        buf[length] = BASE_BACKSLASH
        let short: Byte = match (b) {
            case 0x22 => 0x22
            case 0x5C => 0x5C
            case 0x08 => 0x62
            case 0x0C => 0x66
            case 0x0A => 0x6E
            case 0x0D => 0x72
            case 0x09 => 0x74
            case _ => 0
        }
        if (short != 0) {
            buf[length + 1] = short
            length += 2
            return
        }
        buf[length + 1] = 0x75
        buf[length + 2] = 0x30
        buf[length + 3] = 0x30
        buf[length + 4] = BASE_HEX[Int64(b >> 4)]
        buf[length + 5] = BASE_HEX[Int64(b & 0x0F)]
        length += 6
    }
}

/** The envelope in one pass, `params` decoded in place when `method` came first, as the connection will. */
func baseRpcRead<P>(r: BaseReader, decode: (String, BaseReader) -> P): (?Int64, P) {
    var method: ?String = None
    var id: ?Int64 = None
    var params: ?P = None
    var raw: ?Array<Byte> = None
    r.beginObject()
    while (r.nextKey()) {
        if (r.keyIs("jsonrpc")) {
            if (r.readString() != "2.0") {
                throw FjException("not 2.0")
            }
        } else if (r.keyIs("id")) {
            id = r.readInt64()
        } else if (r.keyIs("method")) {
            method = r.readString()
        } else if (r.keyIs("params")) {
            match (method) {
                case Some(m) => params = decode(m, r)
                case None => raw = r.rawValue()
            }
        } else {
            r.skipValue()
        }
    }
    r.end()
    match ((params, raw)) {
        case (Some(p), _) => (id, p)
        case (None, Some(bytes)) =>
            r.reset(bytes)
            (id, decode(rpcRequired(method, "method"), r))
        case _ => throw FjException("no params")
    }
}

func baseRpcPosition(r: BaseReader): RpcPosition {
    var line: ?UInt32 = None
    var character: ?UInt32 = None
    r.beginObject()
    while (r.nextKey()) {
        if (r.keyIs("line")) {
            line = r.readUInt32()
        } else if (r.keyIs("character")) {
            character = r.readUInt32()
        } else {
            r.skipValue()
        }
    }
    RpcPosition(rpcRequired(line, "line"), rpcRequired(character, "character"))
}

func baseRpcRange(r: BaseReader): RpcRange {
    var start: ?RpcPosition = None
    var end: ?RpcPosition = None
    r.beginObject()
    while (r.nextKey()) {
        if (r.keyIs("start")) {
            start = baseRpcPosition(r)
        } else if (r.keyIs("end")) {
            end = baseRpcPosition(r)
        } else {
            r.skipValue()
        }
    }
    RpcRange(rpcRequired(start, "start"), rpcRequired(end, "end"))
}

func baseRpcChange(r: BaseReader): RpcChange {
    var range: ?RpcRange = None
    var rangeLength: ?UInt32 = None
    var text: ?String = None
    r.beginObject()
    while (r.nextKey()) {
        if (r.keyIs("range")) {
            range = baseRpcRange(r)
        } else if (r.keyIs("rangeLength")) {
            rangeLength = r.readUInt32()
        } else if (r.keyIs("text")) {
            text = r.readString()
        } else {
            r.skipValue()
        }
    }
    RpcChange(range, rangeLength, rpcRequired(text, "text"))
}

func baseRpcDidChange(_: String, r: BaseReader): RpcDidChange {
    var uri: ?String = None
    var version: ?Int32 = None
    var changes: ?Array<RpcChange> = None
    r.beginObject()
    while (r.nextKey()) {
        if (r.keyIs("textDocument")) {
            r.beginObject()
            while (r.nextKey()) {
                if (r.keyIs("uri")) {
                    uri = r.readString()
                } else if (r.keyIs("version")) {
                    version = r.readInt32()
                } else {
                    r.skipValue()
                }
            }
        } else if (r.keyIs("contentChanges")) {
            let list = ArrayList<RpcChange>()
            r.beginArray()
            while (r.nextItem()) {
                list.add(baseRpcChange(r))
            }
            changes = list.toArray()
        } else {
            r.skipValue()
        }
    }
    RpcDidChange(rpcRequired(uri, "uri"), rpcRequired(version, "version"), rpcRequired(changes, "contentChanges"))
}

func baseRpcSymbolParams(_: String, r: BaseReader): String {
    var uri: ?String = None
    r.beginObject()
    while (r.nextKey()) {
        if (r.keyIs("textDocument")) {
            r.beginObject()
            while (r.nextKey()) {
                if (r.keyIs("uri")) {
                    uri = r.readString()
                } else {
                    r.skipValue()
                }
            }
        } else {
            r.skipValue()
        }
    }
    rpcRequired(uri, "uri")
}

func baseRpcWritePosition(w: BaseWriter, position: RpcPosition): Unit {
    w.beginObject()
    w.name("line")
    w.uint32(position.line)
    w.name("character")
    w.uint32(position.character)
    w.endObject()
}

func baseRpcWriteRange(w: BaseWriter, range: RpcRange): Unit {
    w.beginObject()
    w.name("start")
    baseRpcWritePosition(w, range.start)
    w.name("end")
    baseRpcWritePosition(w, range.end)
    w.endObject()
}

func baseRpcWriteSymbol(w: BaseWriter, symbol: RpcSymbol): Unit {
    w.beginObject()
    w.name("name")
    w.string(symbol.name)
    if (let Some(detail) <- symbol.detail) {
        w.name("detail")
        w.string(detail)
    }
    w.name("kind")
    w.int64(symbol.kind)
    w.name("range")
    baseRpcWriteRange(w, symbol.range)
    w.name("selectionRange")
    baseRpcWriteRange(w, symbol.selectionRange)
    if (let Some(children) <- symbol.children) {
        w.name("children")
        w.beginArray()
        for (child in children) {
            baseRpcWriteSymbol(w, child)
        }
        w.endArray()
    }
    w.endObject()
}

func baseRpcWriteResponse(w: BaseWriter, id: Int64, symbols: Array<RpcSymbol>): Array<Byte> {
    w.beginObject()
    w.name("jsonrpc")
    w.string("2.0")
    w.name("id")
    w.int64(id)
    w.name("result")
    w.beginArray()
    for (symbol in symbols) {
        baseRpcWriteSymbol(w, symbol)
    }
    w.endArray()
    w.endObject()
    w.bytes()
}


/** The text of a `didOpen`, read by fjson the way a generated decoder reads it. */
func baseText(r: BaseReader): String {
    var text = ""
    r.beginObject()
    while (r.nextKey()) {
        if (r.keyIs("params")) {
            r.beginObject()
            while (r.nextKey()) {
                if (r.keyIs("textDocument")) {
                    r.beginObject()
                    while (r.nextKey()) {
                        if (r.keyIs("text")) {
                            text = r.readString()
                        } else {
                            r.skipValue()
                        }
                    }
                } else {
                    r.skipValue()
                }
            }
        } else {
            r.skipValue()
        }
    }
    text
}

var baseSink = 0

let BASE_READER = BaseReader(Array<Byte>())
let BASE_WRITER = BaseWriter()

@Test
@Configure[warmup: 1 * Duration.second, minDuration: 3 * Duration.second]
class FjRpcBaseBench {
    @Bench
    func readKeystroke(): Unit {
        BASE_READER.reset(KEYSTROKE)
        baseSink += baseRpcRead(BASE_READER, baseRpcDidChange)[1].changes.size
    }

    @Bench
    func readSymbolRequest(): Unit {
        BASE_READER.reset(SYMBOL_REQUEST)
        baseSink += baseRpcRead(BASE_READER, baseRpcSymbolParams)[1].size
    }

    @Bench
    func readDidOpen64Kb(): Unit {
        BASE_READER.reset(DID_OPEN)
        baseSink += baseText(BASE_READER).size
    }

    @Bench
    func write550SymbolResponse(): Unit {
        BASE_WRITER.clear()
        baseSink += baseRpcWriteResponse(BASE_WRITER, 7, RPC_SYMBOLS).size
    }
}
