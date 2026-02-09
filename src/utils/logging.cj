package cjls.utils

import std.env.{getStdErr, getVariable}
import stdx.log.{setGlobalLogger, LogLevel}
import stdx.logger.SimpleLogger

public func initGlobalLogger(): Unit {
    let logger = SimpleLogger(getStdErr())
    logger.level = getVariable("CJLS_LOG_LEVEL").flatMap(LogLevel.tryParse).getOrDefault {=> LogLevel.ERROR}
    setGlobalLogger(logger)
}

extend LogLevel {
    static func tryParse(value: String): ?LogLevel {
        match (value.toAsciiUpper()) {
            case "OFF" => Some(LogLevel.OFF)
            case "FATAL" => Some(LogLevel.FATAL)
            case "ERROR" => Some(LogLevel.ERROR)
            case "WARN" => Some(LogLevel.WARN)
            case "INFO" => Some(LogLevel.INFO)
            case "DEBUG" => Some(LogLevel.DEBUG)
            case "TRACE" => Some(LogLevel.TRACE)
            case "ALL" => Some(LogLevel.ALL)
            case _ => None
        }
    }
}
