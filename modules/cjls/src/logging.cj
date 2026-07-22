package cjls // cjlint-ignore !G.NAM.02

import std.env.{getStdErr, getVariable}
import stdx.log.{getGlobalLogger, setGlobalLogger, LogLevel, Logger}
import stdx.logger.SimpleLogger

@Frozen
func initGlobalLogger(): Unit {
    let logger = SimpleLogger(getStdErr())
    setGlobalLogger(logger)

    const CJLS_LOG_LEVEL_ENV = "CJLS_LOG_LEVEL"
    logger.level = getVariable(CJLS_LOG_LEVEL_ENV).flatMap {
        s: String => try {
            Some(LogLevel.parse(s))
        } catch (e: UnknownLogLevelException) {
            logWarning(e.message)
            logInfo("setting log leve to INFO as default")
            LogLevel.INFO
        }
    }.getOrDefault {
        =>
            logInfo("log level was not provided, setting INFO as default")
            LogLevel.INFO
    }
}

private const PREFIX = "[cjls] "

@Frozen
func logFatal(msg: String) {
    getGlobalLogger().fatal(PREFIX + msg)
}

@Frozen
func logError(msg: String) {
    getGlobalLogger().error(PREFIX + msg)
}

@Frozen
func logWarning(msg: String) {
    getGlobalLogger().warn(PREFIX + msg)
}

@Frozen
func logInfo(msg: String) {
    getGlobalLogger().info(PREFIX + msg)
}

@Frozen
func logDebug(msg: String) {
    getGlobalLogger().debug(PREFIX + msg)
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
    @Frozen
    UnknownLogLevelException(value: String) {
        super("Unknown log level: ${value}")
    }
}
