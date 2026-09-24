package lsp_codegen

import std.io.{ByteBuffer, readToEnd}
import std.unittest.*
import std.unittest.testmacro.*

func emittedBy(body: (CjEmitter) -> Unit): String {
    let output = ByteBuffer()
    let emitter = CjEmitter(output)
    body(emitter)
    emitter.flush()

    unsafe { String.fromUtf8(readToEnd(output)) }
}

@Test
class CjEmitterTest {
    @TestCase
    func aDocCommentLeavesBlankLinesWithoutTrailingSpace() {
        // arrange
        let dc = DocComment(lines: ["one", "two", "", "three"])
        let expected = """
/**
 * one
 * two
 *
 * three
 */
"""

        // act
        let actual = emittedBy {emitter => emitter.emitln(dc)}

        // assert
        @PowerAssert(expected, actual)
    }

    @TestCase
    func aCommentDelimiterInDocumentationIsDefused() {
        // act
        let escaped = escapedCommentText("matches **" + "/*.ts and ends *" + "/")

        // assert
        @Expect(!escaped.contains("/*"))
        @Expect(!escaped.contains("*/"))
    }
}
