package cjls

import std.collection.ArrayList
import std.io.{InputStream, BufferedInputStream}
import std.convert.Parsable

struct LSPHeader <: Parsable<LSPHeader> & ToString {
    static const CONTENT_TYPE_DEFAULT = "application/vscode-jsonrpc; charset=utf-8"

    @Frozen
    LSPHeader(let contentLength: Int64, let contentType!: String = CONTENT_TYPE_DEFAULT) {}

    @Frozen
    public static func parse(str: String): LSPHeader {
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
                    throw LSPHeaderContentLengthInvalidException(e)
                }
                // even though cjls only supports utf-8 charsets we don't validate it here, because the header field syntax is correct
                case "Content-Type" => contentType = fieldParts[1]
                // unknown field branch
                case _ => continue
            }
        }

        match (contentLength) {
            case None => throw LSPHeaderContentLengthMissingException()
            case Some(v) where v < 0 => throw LSPHeaderContentLengthNegativeException()
            case Some(v) => LSPHeader(v, contentType: contentType)
        }
    }

    @Frozen
    public static func tryParse(str: String): ?LSPHeader {
        try {
            parse(str)
        } catch (_: Exception) {
            None
        }
    }

    @Frozen
    public func toString(): String {
        "Content-Length: ${contentLength}\r\nContent-Type: ${contentType}\r\n"
    }

    @Frozen
    static func parse<T>(input: BufferedInputStream<T>): ?LSPHeader where T <: InputStream {
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
        LSPHeader.parse(fieldsStr)
    }
}

sealed abstract class LSPHeaderException <: Exception {
    init(str: String) {
        super(str)
    }
}

class LSPHeaderContentLengthMissingException <: LSPHeaderException {
    LSPHeaderContentLengthMissingException() {
        super("Required field \"Content-Length\" is missing")
    }

    protected func getClassName() {
        "LSPHeaderContentLengthMissingException"
    }
}

class LSPHeaderContentLengthNegativeException <: LSPHeaderException {
    LSPHeaderContentLengthNegativeException() {
        super("\"Content-Length\" must be non-negative")
    }

    protected func getClassName() {
        "LSPHeaderContentLengthInvalidException"
    }
}

class LSPHeaderContentLengthInvalidException <: LSPHeaderException {
    LSPHeaderContentLengthInvalidException(cause: Exception) {
        super("\"Content-Length\" value is invalid\nCause:${cause}")
    }

    protected func getClassName() {
        "LSPHeaderContentLengthInvalidException"
    }
}
