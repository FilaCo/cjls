package fjson

let HEX: Array<Byte> = [0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66]

/**
 * A JSON writer into one growing byte buffer: no tree, no `String` of the whole, numbers written
 * digit by digit in place, strings copied a run at a time between the bytes they escape. Commas
 * need no stack: every value is preceded by one unless a container or a key was just opened.
 * `bytes()` is a slice of the buffer, what the transport writes after its header.
 */
public class FjWriter {
    private var buf: Array<Byte>
    private var length = 0
    private var needComma = false

    public init(capacity!: Int64 = 1024, swar!: Bool = false) {
        buf = Array<Byte>(capacity, repeat: 0)
        this.swar = swar
    }

    private let swar: Bool

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
        buf[length] = QUOTE
        length++
        var i = 0
        while (i < n) {
            let runEnd = if (swar) { scanEscapes(source, i) } else { scanEscapesScalar(source, i) }
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
        put(QUOTE)
    }

    private func escape(b: Byte): Unit {
        reserve(6)
        buf[length] = BACKSLASH
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
        buf[length + 4] = HEX[Int64(b >> 4)]
        buf[length + 5] = HEX[Int64(b & 0x0F)]
        length += 6
    }
}
