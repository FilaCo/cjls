package lsp

import std.collection.ArrayList
import std.io.{InputStream, BufferedInputStream}
import std.convert.Parsable

public struct Header <: Parsable<Header> {
    public static const CONTENT_TYPE_DEFAULT: String = "application/vscode-jsonrpc; charset=utf-8"

    @Frozen
    public Header(public let contentLength: Int64, public let contentType!: String = CONTENT_TYPE_DEFAULT) {}

    /**
     * @note: caller should trim a header terminator ("\r\n\r\n") from `str`.
     */
    @Frozen
    public static func parse(str: String): Header {
        let fieldsSplitted = str.split("\r\n", removeEmpty: true)
        var contentLength = None<Int64>
        var contentType = CONTENT_TYPE_DEFAULT
        for (rawField in fieldsSplitted) {
            let fieldParts = rawField.split(": ", 2)
            if (fieldParts.size != 2) {
                continue // skip field with no ": " separator
            }
            match (fieldParts[0]) {
                case "Content-Length" => contentLength = try {
                    Int64.parse(fieldParts[1])
                } catch (e: IllegalArgumentException) {
                    throw HeaderContentLengthInvalidException(e)
                }
                // even though we only support utf-8 charsets we don't validate it here, because the header field syntax is correct
                case "Content-Type" => contentType = fieldParts[1]
                // unknown field branch
                case _ => continue
            }
        }

        match (contentLength) {
            case None => throw HeaderContentLengthMissingException()
            case Some(v) where v < 0 => throw HeaderContentLengthNegativeException()
            case Some(v) => Header(v, contentType: contentType)
        }
    }

    @Frozen
    public static func tryParse(str: String): ?Header {
        try {
            parse(str)
        } catch (_: Exception) {
            None
        }
    }

    @Frozen
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

sealed abstract class HeaderException <: Exception {
    init(str: String) {
        super(str)
    }
}

public class HeaderContentLengthMissingException <: HeaderException {
    HeaderContentLengthMissingException() {
        super("Required field \"Content-Length\" is missing")
    }
}

public class HeaderContentLengthNegativeException <: HeaderException {
    HeaderContentLengthNegativeException() {
        super("\"Content-Length\" must be non-negative")
    }
}

public class HeaderContentLengthInvalidException <: HeaderException {
    HeaderContentLengthInvalidException(cause: Exception) {
        super("\"Content-Length\" value is invalid\nCause:${cause}")
    }
}
