package cjls // cjlint-ignore !G.NAM.02

import std.env.{getStdErr, getVariable}
import stdx.log.{setGlobalLogger, LogLevel, Logger}
import stdx.logger.SimpleLogger

@Frozen
func initGlobalLogger(): Logger {
    let logger = SimpleLogger(getStdErr())
    const CJLS_LOG_LEVEL_ENV = "CJLS_LOG_LEVEL"
    if (let Some(logLevelStr) <- getVariable(CJLS_LOG_LEVEL_ENV)) {
        try {
            logger.level = LogLevel.parse(logLevelStr)
        } catch (_: UnknownLogLevelException) {
            logger.level = LogLevel.INFO
            logger.warn("Unknown log level ${logLevelStr}")
            logger.info("Log level was not provided, setting INFO as default")
        }
    } else {
        logger.level = LogLevel.INFO
        logger.info("Log level was not provided, setting INFO as default")
    }

    setGlobalLogger(logger)
    logger
}

extend LogLevel /* <: Parsable<LogLevel> */ {
    /**
     * @throws UnknownLogLevelException - If provided value doesn't match to any known LogLevel
     */
    @Frozen
    static func parse(value: String): LogLevel {
        match (value.toAsciiUpper()) {
            case "OFF" => LogLevel.OFF
            case "FATAL" => LogLevel.FATAL
            case "ERROR" => LogLevel.ERROR
            case "WARN" => LogLevel.WARN
            case "INFO" => LogLevel.INFO
            case "DEBUG" => LogLevel.DEBUG
            case "TRACE" => LogLevel.TRACE
            case "ALL" => LogLevel.ALL
            case _ => throw UnknownLogLevelException(value)
        }
    }
}

class UnknownLogLevelException <: Exception {
    UnknownLogLevelException(value: String) {
        super("Unknown log level: ${value}")
    }
}
