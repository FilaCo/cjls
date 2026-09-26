package ginkgo

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

/**
 * `Root [ outer [ inner [ "x" ] ] ]`: three nodes over the one text.
 */
func stackedTree(outer: TestKind, inner: TestKind): SyntaxNode<TestKind> {
    let b = GreenNodeBuilder<TestKind>()
    b.startNode(Root)
    b.startNode(outer)
    b.startNode(inner)
    b.token(Word, "x")
    b.finishNode()
    b.finishNode()
    b.finishNode()
    SyntaxNode.newRoot(b.finish())
}

@Test
class SyntaxNodePtrTest {
    @TestCase
    func everyNodeIsFoundAgainByItsPointer() {
        // arrange
        let root = sampleTree()

        // act, assert
        for (node in root.descendants()) {
            @Expect(SyntaxNodePtr(node).toNode(root), node)
        }
    }

    @TestCase
    func anEmptyNodeBetweenTwoTokensIsFound() {
        // arrange
        let root = sampleTree()
        let empty = root.descendants().filter {n => n.textRange.isEmpty()}.next().getOrThrow()

        // act
        let found = SyntaxNodePtr(Leaf, TextRange.empty(3)).toNode(root)

        // assert
        @Expect(found, empty)
    }

    @TestCase
    func nodesOverTheSameTextAreToldApartByKind() {
        // arrange
        let root = stackedTree(Inner, Leaf)
        let inner = root.firstChild().getOrThrow()
        let leaf = inner.firstChild().getOrThrow()

        // act, assert
        @Expect(SyntaxNodePtr(root).toNode(root), root)
        @Expect(SyntaxNodePtr(inner).toNode(root), inner)
        @Expect(SyntaxNodePtr(leaf).toNode(root), leaf)
    }

    @TestCase
    func nestedNodesOfOneKindAndRangeResolveToTheInnermost() {
        // arrange
        let root = stackedTree(Inner, Inner)
        let outer = root.firstChild().getOrThrow()
        let inner = outer.firstChild().getOrThrow()

        // act
        let found = SyntaxNodePtr(outer).toNode(root)

        // assert
        @Expect(found, inner)
    }

    @TestCase
    func aPointerResolvesOnAnotherTreeOfTheSameText() {
        // arrange
        let first = sampleTree()
        let second = sampleTree()
        let node = first.descendants().filter {n => n.kind == Inner}.next().getOrThrow()
        let ptr = SyntaxNodePtr(node)

        // act
        let found = ptr.toNode(second)

        // assert
        @Expect(found.root(), second)
        @Expect(SyntaxNodePtr(found), ptr)
        @Expect(found.text(), "bc")
    }

    @TestCase
    func aPointerToANodeATreeDoesNotHaveThrows() {
        // arrange
        let root = sampleTree()

        // act, assert
        @Expect(SyntaxNodePtr(Inner, TextRange(0, 1)).tryToNode(root), None<SyntaxNode<TestKind>>)
        @Expect(SyntaxNodePtr(Leaf, TextRange(0, 99)).tryToNode(root), None<SyntaxNode<TestKind>>)
        @AssertThrows[IllegalArgumentException](SyntaxNodePtr(Inner, TextRange(0, 1)).toNode(root))
    }

    @TestCase
    func pointersAreEqualByKindAndRange() {
        // arrange
        let root = sampleTree()
        let inner = root.descendants().filter {n => n.kind == Inner}.next().getOrThrow()

        // act, assert
        @Expect(SyntaxNodePtr(inner), SyntaxNodePtr(Inner, inner.textRange))
        @Expect(SyntaxNodePtr(inner).hashCode(), SyntaxNodePtr(Inner, inner.textRange).hashCode())
        @Expect(SyntaxNodePtr(inner) != SyntaxNodePtr(Leaf, inner.textRange))
        @Expect(SyntaxNodePtr(inner).toString(), "Inner@${inner.textRange}")
    }
}

@Test
class AstPtrTest {
    @TestCase
    func anAstPtrResolvesToItsView() {
        // arrange
        let root = sampleTree()
        let view = Nested.cast(root.descendants().filter {n => n.kind == Inner}.next().getOrThrow()).getOrThrow()

        // act
        let found = AstPtr<TestKind, Nested>(view).toNode(root)

        // assert
        @Expect(found.syntax, view.syntax)
    }

    @TestCase
    func anAstPtrToANodeThatIsNotItsTypeThrows() {
        // arrange
        let root = sampleTree()
        let ptr = AstPtr<TestKind, Nested>(SyntaxNodePtr(root))

        // act, assert
        @AssertThrows[IllegalArgumentException](ptr.toNode(root))
    }

    @TestCase
    func anAstPtrOnATreeWhereItsRangeHoldsAnotherKindThrows() {
        // arrange
        let inners = stackedTree(Inner, Inner)
        let leaves = stackedTree(Leaf, Leaf)
        let ptr = AstPtr<TestKind, Nested>(Nested.cast(inners.firstChild().getOrThrow()).getOrThrow())

        // act, assert
        @AssertThrows[IllegalArgumentException](ptr.toNode(leaves))
    }
}
