package lsp_codegen

import std.unittest.*
import std.unittest.testmacro.*

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
