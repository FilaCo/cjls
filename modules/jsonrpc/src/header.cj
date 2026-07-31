package jsonrpc

import std.collection.ArrayList
import std.io.{InputStream, BufferedInputStream}
import std.convert.Parsable

public struct Header <: Parsable<Header> {
    static const CONTENT_TYPE_DEFAULT: String = "application/vscode-jsonrpc; charset=utf-8"

    public Header(public let contentLength: Int32, public let contentType!: String = CONTENT_TYPE_DEFAULT) {}

    /**
     * @note: caller should trim a header terminator ("\r\n\r\n") from `str`.
     *
     * @throws TransportException - if header is invalid
     */
    public static func parse(str: String): Header {
        let fieldsSplitted = str.split("\r\n", removeEmpty: true)
        var contentLength = None<Int32>
        var contentType = CONTENT_TYPE_DEFAULT
        for (rawField in fieldsSplitted) {
            let fieldParts = rawField.split(": ", 2)
            if (fieldParts.size != 2) {
                continue // skip field with no ": " separator
            }
            match (fieldParts[0]) {
                case "Content-Length" => contentLength = try {
                    Int32.parse(fieldParts[1])
                } catch (e: IllegalArgumentException) {
                    throw TransportException("\"Content-Length\" value is invalid\nCause:${e}")
                }
                // even though we only support utf-8 charsets we don't validate it here, because the header field syntax is correct
                case "Content-Type" => contentType = fieldParts[1]
                // unknown field branch
                case _ => continue
            }
        }

        match (contentLength) {
            case None => throw TransportException("Required field \"Content-Length\" is missing")
            case Some(v) where v < 0 => throw TransportException("\"Content-Length\" must be non-negative")
            case Some(v) => Header(v, contentType: contentType)
        }
    }

    public static func tryParse(str: String): ?Header {
        try {
            parse(str)
        } catch (_: TransportException) {
            None
        }
    }

    public static func parse<T>(input: BufferedInputStream<T>): ?Header where T <: InputStream {
        const HEADER_TERMINATOR: VArray<Byte, $4> = [b'\r', b'\n', b'\r', b'\n']
        let fieldsBuf = ArrayList<Byte>()
        var terminated = false
        while (let Some(curByte) <- input.readByte()) {
            fieldsBuf.add(curByte)
            if (fieldsBuf.size < HEADER_TERMINATOR.size) {
                continue
            }

            terminated = true
            // VArray and Array are not Equatable, so we compare them manually
            let offset = fieldsBuf.size - HEADER_TERMINATOR.size
            for (idx in 0..HEADER_TERMINATOR.size) {
                if (fieldsBuf[idx + offset] != HEADER_TERMINATOR[idx]) {
                    terminated = false
                    break
                }
            }

            if (terminated) {
                break
            }
        }

        if (!terminated) {
            return None
        }

        let fieldsStr = String.fromUtf8(fieldsBuf[..fieldsBuf.size - HEADER_TERMINATOR.size].toArray())
        Header.parse(fieldsStr)
    }
}
