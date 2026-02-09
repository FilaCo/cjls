package cjls // cjlint-ignore !G.NAM.02

import std.env.{getStdErr, getVariable}
import stdx.log.{setGlobalLogger, LogLevel}
import stdx.logger.SimpleLogger

protected func initGlobalLogger(): Unit {
    let logger = SimpleLogger(getStdErr())
    const CJLS_LOG_LEVEL_ENV = "CJLS_LOG_LEVEL"
    logger.level = getVariable(CJLS_LOG_LEVEL_ENV).flatMap(LogLevel.tryParse).getOrDefault {=> LogLevel.ERROR}
    setGlobalLogger(logger)
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

    static func tryParse(value: String): ?LogLevel {
        try {
            Some(parse(value))
        } catch (_) {
            None
        }
    }
}

public class UnknownLogLevelException <: Exception {
    protected UnknownLogLevelException(value: String) {
        super("Unknown log level: ${value}")
    }

    protected func getClassName() {
        "UnknownLogLevelException"
    }
}
