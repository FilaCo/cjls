package cjls

import std.env.getStdIn
import std.io.{InputStream, BufferedInputStream, ByteBuffer}
import stdx.log.Logger
import stdx.encoding.json.stream.{JsonDeserializable, JsonSerializable, JsonReader, JsonWriter, JsonToken}
import lsp.{Header, HeaderException, Message}

private const EXIT_CODE_SUCCESS = 0
private const EXIT_CODE_FAILURE = 1

@Frozen
func runServer() {
    let logger = initGlobalLogger()
    let input = BufferedInputStream(getStdIn())
    logger.info("cjls is running")
    mainLoop(logger, input)
}

@Frozen
private func mainLoop<T>(logger: Logger, input: BufferedInputStream<T>) where T <: InputStream {
    while (true) {
    }

    EXIT_CODE_SUCCESS
}
