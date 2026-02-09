package cjls

import stdx.log.{getGlobalLogger, Logger}
import std.io.{InputStream, StringReader}
import std.env.getStdIn

protected func runServer() {
    let logger = getGlobalLogger()
    logger.info("server will start")
    logger.info("server did shutdown")
}