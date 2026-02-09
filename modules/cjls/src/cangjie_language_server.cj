package cjls

import stdx.log.{getGlobalLogger, Logger}
import cjls_interface.{runServer, CangjieLanguageServerDatabase}
import std.io.{InputStream, StringReader}
import std.env.getStdIn

/**
 * Cangjie Language Server driver class.
 */
public class CangjieLanguageServer {
    public func serve(): Unit {
        initGlobalLogger()
        runServer {
            _: CangjieLanguageServerDatabase =>
                let logger = getGlobalLogger()
                logger.info("Cangjie language server started")
        }
    }
}
