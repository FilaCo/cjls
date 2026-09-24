package cjls

import stdx.log.LogLevel

@Test
class LogLevelTest {
    @TestCase[sample in [
        ("OFF", Some(LogLevel.OFF)),
        ("fatal", Some(LogLevel.FATAL)),
        ("Error", Some(LogLevel.ERROR)),
        ("WARN", Some(LogLevel.WARN)),
        ("INFO", Some(LogLevel.INFO)),
        ("debug", Some(LogLevel.DEBUG)),
        ("TRACE", Some(LogLevel.TRACE)),
        ("ALL", Some(LogLevel.ALL)),
        ("verbose", None)
    ]]
    func aLevelIsReadByItsNameInAnyCase(sample: (String, ?LogLevel)) {
        // arrange
        let (name, expected) = sample

        // act
        let level = parseLogLevel(name)

        // assert
        @Expect(expected, level)
    }
}
