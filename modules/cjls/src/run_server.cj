package cjls

import stdx.log.{getGlobalLogger, Logger}
import std.env.getStdIn

// const CONTENT_LENGTH_FIELD_NAME = "Content-Length"
// const CONTENT_TYPE_FIELD_NAME = "Content-Type"
// let FIELD_NAMES = [CONTENT_LENGTH_FIELD_NAME, CONTENT_TYPE_FIELD_NAME]
// let FIELDS_COUNT = FIELD_NAMES.size
// let VALID_ENCODINGS = ["utf-8", "utf8"]
// const LF = r'\n'
// const CR = r'\r'
// const COLON = r':'
// const SEMI = r';'
// const SPACE = r' '
// const EQ = r'='
// let NL = "${CR}${LF}"
// let FIELD_SEPARATOR = "${COLON}${SPACE}"
// let CONTENT_TYPE_SEPARATOR = "${SEMI}${SPACE}"
const BUF_SIZE = 4096;

@Frozen
func runServer() {
    let logger = getGlobalLogger()
    let buf = Array<Byte>(BUF_SIZE, repeat: 0)
    logger.info("cjls is running")
    while (true) {
        let size = getStdIn().read(buf)
        
    }
}

struct LSPHeader {}

func parseHeader(buf: Array<Byte>, size: Int64) {}