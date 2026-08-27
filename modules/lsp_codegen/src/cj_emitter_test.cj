package lsp_codegen

import std.io.{ByteBuffer, readToEnd}
import std.unittest.*
import std.unittest.testmacro.*

@Test
class CjEmitterTest {
    @TestCase
    func smokeBlockComment() {
        // arrange
        let dc = DocComment(
            lines: [
                "one",
                "two",
                "",
                "three"
            ]
        )
        let output = ByteBuffer()
        let sut = CjEmitter(output)

        let expected = """
/**
 * one
 * two
 *
 * three
 */
"""

        // act
        sut.emitln(dc)
        sut.flush()
        let actual = unsafe { String.fromUtf8(readToEnd(output)) }

        // assert
        @PowerAssert(expected, actual)
    }
}
