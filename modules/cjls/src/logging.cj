package cjls // cjlint-ignore !G.NAM.02

import std.env.{getStdErr, getVariable}
import stdx.log.{getGlobalLogger, setGlobalLogger, LogLevel, Logger}
import stdx.logger.SimpleLogger

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

func logFatal(msg: String) {
    getGlobalLogger().fatal(PREFIX + msg)
}

func logError(msg: String) {
    getGlobalLogger().error(PREFIX + msg)
}

func logWarning(msg: String) {
    getGlobalLogger().warn(PREFIX + msg)
}

func logInfo(msg: String) {
    getGlobalLogger().info(PREFIX + msg)
}

func logDebug(msg: String) {
    getGlobalLogger().debug(PREFIX + msg)
}

extend LogLevel /* <: Parsable<LogLevel> */ {
    /**
     * @throws UnknownLogLevelException - If provided value doesn't match to any known LogLevel
     */
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

    protected override func getClassName(): String {
        "UnknownLogLevelException"
    }
}
