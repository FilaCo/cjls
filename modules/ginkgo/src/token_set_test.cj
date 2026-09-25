package ginkgo

import std.unittest.*
import std.unittest.testmacro.*

@Test
class TokenSetTest {
    @TestCase
    func containsExactlyTheKindsItWasMadeOf() {
        // arrange
        let sut = TokenSet<TestKind>([Inner, Word])

        // act & assert
        @Expect(!sut.contains(Root))
        @Expect(sut.contains(Inner))
        @Expect(!sut.contains(Leaf))
        @Expect(sut.contains(Word))
        @Expect(!sut.contains(Space))
    }

    @TestCase
    func anEmptySetContainsNothing() {
        // act & assert
        @Expect(!TokenSet<TestKind>.empty().contains(Root))
        @Expect(!TokenSet<TestKind>([]).contains(Space))
    }

    @TestCase
    func aUnionHoldsTheKindsOfBoth() {
        // act
        let sut = TokenSet<TestKind>([Root]).union(TokenSet<TestKind>([Space]))

        // assert
        @Expect(sut, TokenSet<TestKind>([Space, Root]))
        @Expect(sut != TokenSet<TestKind>([Root]))
    }
}
