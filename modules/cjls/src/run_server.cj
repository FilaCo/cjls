package cjls

import stdx.log.Logger
import std.env.getStdIn
import std.io.{InputStream, BufferedInputStream}

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
        let header = try {
            if (let Some(header) <- LSPHeader.parse(input)) {
                logger.debug("parsed request header:\n${header}")
                header
            } else {
                logger.info("got EOF while parsing header")
                break
            }
        } catch (e: LSPHeaderException) {
            logger.error("Unable to parse request header", ("error", e.message))
            return EXIT_CODE_FAILURE
        }
    }

    EXIT_CODE_SUCCESS
}
