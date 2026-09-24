package cjls // cjlint-ignore !G.NAM.02

import std.env.{getStdErr, getVariable}
import stdx.log.{LogLevel, Logger}
import stdx.logger.SimpleLogger

const LOG_LEVEL_VARIABLE = "CJLS_LOG_LEVEL"

/**
 * At the level `CJLS_LOG_LEVEL` names, `INFO` if it names none.
 */
func stderrLogger(): Logger {
    let logger = SimpleLogger(getStdErr())
    logger.level = LogLevel.INFO
    if (let Some(name) <- getVariable(LOG_LEVEL_VARIABLE)) {
        match (parseLogLevel(name)) {
            case Some(level) => logger.level = level
            case None => logger.warn("unknown log level, using INFO", [(LOG_LEVEL_VARIABLE, name)])
        }
    }
    logger
}

func parseLogLevel(name: String): ?LogLevel {
    match (name.toAsciiUpper()) {
        case "OFF" => LogLevel.OFF
        case "FATAL" => LogLevel.FATAL
        case "ERROR" => LogLevel.ERROR
        case "WARN" => LogLevel.WARN
        case "INFO" => LogLevel.INFO
        case "DEBUG" => LogLevel.DEBUG
        case "TRACE" => LogLevel.TRACE
        case "ALL" => LogLevel.ALL
        case _ => None
    }
}
