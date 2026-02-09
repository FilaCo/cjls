package cjls.utils

import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.LogLevel

@Test
class LogLevelExtensionTest {
    @TestCase[
        pairs in [
             ("OFF", Some(LogLevel.OFF)), 
             ("FATAL", Some(LogLevel.FATAL)), 
             ("ERROR", Some(LogLevel.ERROR)), 
             ("WARN", Some(LogLevel.WARN)), 
             ("INFO", Some(LogLevel.INFO)), 
             ("DEBUG", Some(LogLevel.DEBUG)), 
             ("TRACE", Some(LogLevel.TRACE)), 
             ("ALL", Some(LogLevel.ALL)),
             ("WTF", None)
        ]
    ]
    func smoke(pairs: (String, ?LogLevel)) {
        // arrange
        let (input, expected) = pairs
        // act
        let actual = LogLevel.tryParse(input)
        // assert
        @PowerAssert(expected == actual)
    }
}
