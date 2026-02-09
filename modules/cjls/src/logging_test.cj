package cjls

import std.unittest.* // cjlint-ignore !G.PKG.01
import std.unittest.testmacro.* // cjlint-ignore !G.PKG.01
import stdx.log.LogLevel

@Test
class LogLevelExtensionTest {
    @TestCase[pairs in [ 
("OFF", LogLevel.OFF), 
("FATAL", LogLevel.FATAL), 
("ERROR", LogLevel.ERROR), 
("WARN", LogLevel.WARN), 
("INFO", LogLevel.INFO), 
("DEBUG", LogLevel.DEBUG), 
("TRACE", LogLevel.TRACE), 
("ALL", LogLevel.ALL) 
 ] 
]
    func smoke(pairs: (String, LogLevel)) {
        // arrange
        let (input, expected) = pairs
        // act
        let actual = LogLevel.parse(input)
        // assert
        @PowerAssert(expected == actual)
    }

    @TestCase
    func unknownLogLevel() {
        // arrange
        let input = "wtf"
        // act
        // assert
        @AssertThrows[UnknownLogLevelException](LogLevel.parse(input))
    }
}
