package jsonrpc

import std.collection.ArrayList
import std.io.{InputStream, BufferedInputStream}
import std.convert.Parsable

struct Header {
    Header(let contentLength: Int32) {}

    /**
     * Fields other than `Content-Length` are skipped: nothing here depends on them.
     *
     * @param str - the header without its terminating "\r\n\r\n"
     * @throws TransportException - if the header is invalid
     */
    static func parse(str: String): Header {
        var contentLength = None<Int32>
        for (rawField in str.split("\r\n", removeEmpty: true)) {
            let parts = rawField.split(": ", 2)
            if (parts.size == 2 && parts[0] == "Content-Length") {
                contentLength = try {
                    Int32.parse(parts[1])
                } catch (e: IllegalArgumentException) {
                    throw TransportException("\"Content-Length\" value is invalid\nCause: ${e.message}")
                }
            }
        }

        match (contentLength) {
            case None => throw TransportException("Required field \"Content-Length\" is missing")
            case Some(v) where v < 0 => throw TransportException("\"Content-Length\" must be non-negative")
            case Some(v) => Header(v)
        }
    }

    /**
     * Reads up to and including the terminator, and not a byte of the content after it.
     *
     * @return `None` if the stream ends first
     * @throws TransportException - if the header is invalid
     */
    static func read<T>(input: BufferedInputStream<T>): ?Header where T <: InputStream {
        let bytes = ArrayList<Byte>()
        while (let Some(byte) <- input.readByte()) {
            bytes.add(byte)
            let n = bytes.size
            if (n >= 4 && bytes[n - 4] == b'\r' && bytes[n - 3] == b'\n' && bytes[n - 2] == b'\r' && byte == b'\n') {
                return Header.parse(String.fromUtf8(bytes[..n - 4].toArray()))
            }
        }
        None
    }
}
