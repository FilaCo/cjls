package ginkgo

import std.unittest.*
import std.unittest.testmacro.*

@Test
class GreenTest {
    @TestCase
    func aNodeCoversExactlyTheTextOfItsChildren() {
        // act
        let root = sampleTree().green

        // assert
        @Expect(root.toString(), "a bc d")
        @Expect(root.textLen, 6)
        @Expect(root.childCount, 5)
        @Expect(root.childOffset(2), 2)
        @Expect(root.childOffset(4), 5)
    }

    @TestCase
    func equalTokensAreOneObject() {
        // arrange
        let b = GreenNodeBuilder<TestKind>()
        b.startNode(Root)
        b.token(Word, "x")
        b.token(Space, " ")
        b.token(Word, "x")
        b.finishNode()

        // act
        let root = b.finish()

        // assert
        @Expect(refEq(root.child(0).asToken().getOrThrow(), root.child(2).asToken().getOrThrow()))
    }

    @TestCase
    func equalSmallNodesAreOneObject() {
        // arrange
        let b = GreenNodeBuilder<TestKind>()
        b.startNode(Root)
        for (_ in 0..2) {
            b.startNode(Leaf)
            b.token(Word, "x")
            b.finishNode()
        }
        b.finishNode()

        // act
        let root = b.finish()

        // assert
        @Expect(refEq(root.child(0).asNode().getOrThrow(), root.child(1).asNode().getOrThrow()))
    }

    @TestCase
    func aNodeStartedAtACheckpointTakesInWhatWasBuiltSince() {
        // arrange
        let b = GreenNodeBuilder<TestKind>()
        b.startNode(Root)
        b.token(Word, "a")
        let cp = b.checkpoint()
        b.token(Word, "b")
        b.token(Word, "c")

        // act
        b.startNodeAt(cp, Inner)
        b.finishNode()
        b.finishNode()

        // assert
        let dump = SyntaxNode.newRoot(b.finish()).debugDump()
        @Expect(dump, "Root@0..3\n  Word@0..1 \"a\"\n  Inner@1..3\n    Word@1..2 \"b\"\n    Word@2..3 \"c\"\n")
    }

    @TestCase
    func aCheckpointOutsideTheOpenNodeIsRefused() {
        // arrange
        let b = GreenNodeBuilder<TestKind>()
        b.startNode(Root)
        let cp = b.checkpoint()
        b.startNode(Inner)

        // act & assert
        @AssertThrows[IllegalStateException](b.startNodeAt(cp, Leaf))
    }

    @TestCase
    func finishRefusesAnythingButOneClosedNode() {
        // arrange
        let open = GreenNodeBuilder<TestKind>()
        open.startNode(Root)
        let empty = GreenNodeBuilder<TestKind>()
        let unbalanced = GreenNodeBuilder<TestKind>()

        // act & assert
        @AssertThrows[IllegalStateException](open.finish())
        @AssertThrows[IllegalStateException](empty.finish())
        @AssertThrows[IllegalStateException](unbalanced.finishNode())
    }

    @TestCase
    func equalityIsStructural() {
        // arrange
        let one = GreenNode(Root, [GreenElement.Token(GreenToken(Word, "x"))])
        let other = GreenNode(Root, [GreenElement.Token(GreenToken(Word, "x"))])
        let different = GreenNode(Root, [GreenElement.Token(GreenToken(Word, "y"))])

        // act & assert
        @Expect(one == other)
        @Expect(one.hashCode(), other.hashCode())
        @Expect(one != different)
    }

    @TestCase
    func spliceReplacesARunOfChildren() {
        // arrange
        let root = sampleTree().green
        let z = GreenElement.Token(GreenToken(Word, "zz"))

        // act
        let spliced = root.spliceChildren(1, 4, [z])
        let inserted = root.insertChild(5, z)
        let removed = root.removeChild(0)

        // assert
        @Expect(spliced.toString(), "azzd")
        @Expect(inserted.toString(), "a bc dzz")
        @Expect(removed.toString(), " bc d")
        @Expect(root.toString(), "a bc d")
        @AssertThrows[IndexOutOfBoundsException](root.spliceChildren(3, 6, []))
    }
}
