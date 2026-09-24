package ginkgo

import std.unittest.*
import std.unittest.testmacro.*

@Test
class TextRangeTest {
    @TestCase
    func containsExcludesTheEndAndContainsInclusiveDoesNot() {
        // arrange
        let range = TextRange(2, 5)

        // act & assert
        @Expect(range.contains(2))
        @Expect(!range.contains(5))
        @Expect(range.containsInclusive(5))
        @Expect(!range.containsInclusive(1))
        @Expect(range.len, 3)
    }

    @TestCase
    func intersectIsEmptyWhenTouchingAndNoneWhenApart() {
        // act & assert
        @Expect(TextRange(0, 4).intersect(TextRange(2, 6)).getOrThrow(), TextRange(2, 4))
        @Expect(TextRange(0, 2).intersect(TextRange(2, 6)).getOrThrow(), TextRange(2, 2))
        @Expect(TextRange(0, 1).intersect(TextRange(2, 6)).isNone())
        @Expect(TextRange(0, 1).cover(TextRange(4, 6)), TextRange(0, 6))
    }

    @TestCase
    func aBackwardRangeIsRefused() {
        // act & assert
        @AssertThrows[IllegalArgumentException](TextRange(3, 2))
        @AssertThrows[IllegalArgumentException](TextRange(-1, 2))
    }
}
