package lsp.base

import std.io.{InputStream, StringReader}
import std.convert.Parsable
import std.collection.collectArray

public type LspContentLength = UInt64

public type LspContentType = String

public struct LspHeader {
    private let _contentLength: LspContentLength
    private let _contentType: ?LspContentType

    protected LspHeader(contentLength!: LspContentLength, contentType!: ?LspContentType = None) {
        _contentLength = contentLength
        _contentType = contentType
    }

    public prop contentLength: LspContentLength {
        get() {
            _contentLength
        }
    }

    public prop contentType: LspContentType {
        get() {
            const DEFAULT_CONTENT_TYPE = "application/vscode-jsonrpc; charset=utf-8"
            _contentType.getOrDefault {=> DEFAULT_CONTENT_TYPE}
        }
    }

    /**
     * @throws LspRequestHeaderUnknownFieldNameException - If unknown header field name provided.
     * @throws LspRequestHeaderInvalidFieldFormatException - If header field has wrong format.
     */
    public static func read<InputT>(input: StringReader<InputT>): LspHeader where InputT <: InputStream {
        let rawFields = readRawFields(input)

        var contentLength = None<String>
        var contentType = None<String>
        for (rawField in rawFields) {
            if (rawField.isEmpty()) {
                continue
            }
            let parts = rawField.split(FIELD_SEPARATOR, 2)
            if (parts.size != 2) {
                throw LspRequestHeaderInvalidFieldFormatException(rawField)
            }
            let (name, value) = (parts[0], parts[1])
            match (name) {
                case s where s == CONTENT_LENGTH_FIELD_NAME => contentLength = value
                case s where s == CONTENT_TYPE_FIELD_NAME => contentType = value
                case _ => throw LspRequestHeaderUnknownFieldNameException(expectedNames: FIELD_NAMES, actualName: name)
            }
        }

        LspHeader(contentLength: parseContentLength(contentLength), contentType: parseContentType(contentType))
    }

    protected static const CONTENT_LENGTH_FIELD_NAME = "Content-Length"
    protected static const CONTENT_TYPE_FIELD_NAME = "Content-Type"
    private static let FIELD_NAMES = [CONTENT_LENGTH_FIELD_NAME, CONTENT_TYPE_FIELD_NAME]
    private static let FIELDS_COUNT = FIELD_NAMES.size
    private static let VALID_ENCODINGS = ["utf-8", "utf8"]

    private static const LF = r'\n'
    private static const CR = r'\r'
    private static const COLON = r':'
    private static const SEMI = r';'
    private static const SPACE = r' '
    private static const EQ = r'='
    private static let NL = "${CR}${LF}"
    private static let FIELD_SEPARATOR = "${COLON}${SPACE}"
    private static let CONTENT_TYPE_SEPARATOR = "${SEMI}${SPACE}"

    /**
     * @throws LspRequestHeaderInvalidFieldsCountException - If header fields count doesn't conform LSP specification.
     */
    private static func readRawFields<InputT>(input: StringReader<InputT>): Array<String> where InputT <: InputStream {
        let rawFields = Array<String>(FIELDS_COUNT, repeat: unsafe { zeroValue<String>() })
        var curField = 0
        // in-place called lambda is here to make cjlint happy for `sb` variable scope
        {
            =>
                let sb = StringBuilder()
                while (let Some(line) <- input.readUntil(LF) && curField < FIELDS_COUNT) {
                    if (line.endsWith(NL)) {
                        let lineSize = line.size - NL.size
                        // Cut off the NL
                        sb.append(line[..lineSize])
                        rawFields[curField] = sb.toString()
                        curField += 1
                        sb.reset()
                    } else {
                        sb.append(line)
                    }
                }
        }()

        if (curField != FIELDS_COUNT) {
            throw LspRequestHeaderInvalidFieldsCountException(expectedCount: FIELDS_COUNT, actualCount: curField)
        }

        rawFields
    }

    private static func parseContentLength(value: ?String): LspContentLength {
        value.map(LspContentLength.parse).getOrThrow {=> LspRequestHeaderContentLengthFieldMissingException()}
    }

    /**
     * @throws LspRequestHeaderInvalidFieldFormatException - If Content-Type field has wrong value format
     */
    private static func parseContentType(value: ?String): ?LspContentType {
        if (let Some(value) <- value) {
            let parts = value.split(CONTENT_TYPE_SEPARATOR, 2)
            if (parts.size != 2) {
                throw LspRequestHeaderInvalidFieldFormatException("${CONTENT_TYPE_FIELD_NAME}: ${value}")
            }
            let encoding = parts[1]
            let encodingParts = value.split("${EQ}", 2)
            if (encodingParts.size != 2) {
                throw LspRequestHeaderInvalidFieldFormatException("${CONTENT_TYPE_FIELD_NAME}: ${value}")
            }
            if (VALID_ENCODINGS.contains(encodingParts[1])) {
                Some(value)
            }
        }

        None
    }
}

public class LspRequestHeaderInvalidFieldsCountException <: Exception {
    protected LspRequestHeaderInvalidFieldsCountException(expectedCount!: Int64, actualCount!: Int64) {
        super("Invalid header fields count. Expected: ${expectedCount}, actual: ${actualCount} ")
    }

    protected func getClassName() {
        "LspRequestHeaderInvalidFieldsCountException"
    }
}

public class LspRequestHeaderUnknownFieldNameException<ExpectedNamesT> <: Exception where ExpectedNamesT <: Iterable<String> {
    protected LspRequestHeaderUnknownFieldNameException(expectedNames!: ExpectedNamesT, actualName!: String) {
        super("Invalid header field name. Expected one of ${expectedNames |> collectArray}, actual: ${actualName} ")
    }

    protected func getClassName() {
        "LspRequestHeaderUnknownFieldNameException"
    }
}

public class LspRequestHeaderInvalidFieldFormatException <: Exception {
    protected LspRequestHeaderInvalidFieldFormatException(field: String) {
        super("Invalid field format: ${field}")
    }

    protected func getClassName() {
        "LspRequestHeaderInvalidFieldFormatException"
    }
}

public class LspRequestHeaderContentLengthFieldMissingException <: Exception {
    protected LspRequestHeaderContentLengthFieldMissingException() {
        super("Required field ${LspHeader.CONTENT_TYPE_FIELD_NAME} is missing")
    }

    protected func getClassName() {
        "LspRequestHeaderContentLengthFieldMissingException"
    }
}
