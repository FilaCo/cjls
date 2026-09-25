package ginkgo

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class SyntaxTest {
    let root = sampleTree()

    func inner(): SyntaxNode<TestKind> {
        root.firstChild().getOrThrow()
    }

    @TestCase
    func debugDumpShowsEveryNodeAndToken() {
        // act
        let dump = root.debugDump()

        // assert
        @Expect(dump, "Root@0..6\n" +
            "  Word@0..1 \"a\"\n" +
            "  Space@1..2 \" \"\n" +
            "  Inner@2..4\n" +
            "    Word@2..3 \"b\"\n" +
            "    Leaf@3..3\n" +
            "    Word@3..4 \"c\"\n" +
            "  Space@4..5 \" \"\n" +
            "  Leaf@5..6\n" +
            "    Word@5..6 \"d\"\n")
    }

    @TestCase
    func childrenSkipTokensAndChildrenWithTokensDoNot() {
        // act
        let nodes = collectArray(root.children().map {n => n.kind.toString()})
        let all = collectArray(root.childrenWithTokens().map {el => el.kind.toString()})

        // assert
        @Expect(String.join(nodes, delimiter: ","), "Inner,Leaf")
        @Expect(String.join(all, delimiter: ","), "Word,Space,Inner,Space,Leaf")
    }

    @TestCase
    func siblingsAndParentsLeadWhereExpected() {
        // arrange
        let inner = inner()
        let leaf = root.lastChild().getOrThrow()

        // act & assert
        @Expect(inner.textRange, TextRange(2, 4))
        @Expect(inner.nextSibling().getOrThrow() == leaf)
        @Expect(leaf.prevSibling().getOrThrow() == inner)
        @Expect(inner.prevSibling().isNone())
        @Expect(inner.parent.getOrThrow() == root)
        @Expect(root.parent.isNone())
        @Expect(inner.nextSiblingOrToken().getOrThrow().kind, Space)
        @Expect(leaf.root() == root)
        @Expect(leaf.ancestors().count(), 2)
        @Expect(inner.siblings(Direction.Next).count(), 2)
        @Expect(leaf.siblingsWithTokens(Direction.Prev).count(), 5)
    }

    @TestCase
    func twoValuesForOneNodeAreEqual() {
        // act
        let one = root.firstChild().getOrThrow()
        let other = root.children().next().getOrThrow()

        // assert
        @Expect(one == other)
        @Expect(one.hashCode(), other.hashCode())
        @Expect(one != root.lastChild().getOrThrow())
    }

    @TestCase
    func descendantsAreInPreorder() {
        // act
        let nodes = collectArray(root.descendants().map {n => n.kind.toString()})
        let tokens = collectArray(root.descendantsWithTokens().filter {el => el.asToken().isSome()}
            .map {el => el.toString()})
        let events = collectArray(inner().preorder().map {
            e => match (e) {
                case Enter(n) => "+${n.kind}"
                case Leave(n) => "-${n.kind}"
            }
        })

        // assert
        @Expect(String.join(nodes, delimiter: ","), "Root,Inner,Leaf,Leaf")
        @Expect(String.join(tokens), "a bc d")
        @Expect(String.join(events, delimiter: ","), "+Inner,+Leaf,-Leaf,-Inner")
    }

    @TestCase
    func firstAndLastTokenSkipEmptyNodes() {
        // arrange
        let empty = inner().children().next().getOrThrow()

        // act & assert
        @Expect(root.firstToken().getOrThrow().text(), "a")
        @Expect(root.lastToken().getOrThrow().text(), "d")
        @Expect(empty.firstToken().isNone())
    }

    @TestCase
    func nextAndPrevTokenCrossNodes() {
        // arrange
        let b = inner().firstToken().getOrThrow()

        // act
        var texts = ArrayList<String>()
        var current = root.firstToken()
        while (let Some(t) <- current) {
            texts.add(t.text())
            current = t.nextToken()
        }

        // assert
        @Expect(String.join(texts.toArray()), "a bc d")
        @Expect(b.nextToken().getOrThrow().text(), "c")
        @Expect(b.prevToken().getOrThrow().text(), " ")
        @Expect(root.lastToken().getOrThrow().nextToken().isNone())
        @Expect(root.firstToken().getOrThrow().prevToken().isNone())
    }

    @TestCase
    func tokenAtOffsetFindsTheTokenOrThePairAround() {
        // act
        let inside = root.tokenAtOffset(0)
        let between = root.tokenAtOffset(3)
        let end = root.tokenAtOffset(6)
        let outside = root.tokenAtOffset(7)

        // assert
        @Expect(inside.rightBiased().getOrThrow().text(), "a")
        match (between) {
            case Between(left, right) =>
                @Expect(left.text(), "b")
                @Expect(right.text(), "c")
            case _ => @Fail("expected two tokens at offset 3")
        }
        @Expect(end.leftBiased().getOrThrow().text(), "d")
        @Expect(outside.leftBiased().isNone())
    }

    @TestCase
    func coveringElementIsTheDeepestOneContainingTheRange() {
        // act & assert
        @Expect(root.coveringElement(TextRange(2, 3)).toString(), "b")
        @Expect(root.coveringElement(TextRange(2, 4)).kind, Inner)
        @Expect(root.coveringElement(TextRange(1, 4)).kind, Root)
        @AssertThrows[IllegalArgumentException](root.coveringElement(TextRange(5, 9)))
    }

    @TestCase
    func replacingANodeBuildsANewRootAndLeavesTheOldOne() {
        // arrange
        let replacement = GreenNode([GreenElement.Token(GreenToken(Word, "xyz"))], Leaf)
        let d = root.lastToken().getOrThrow()

        // act
        let newRoot = inner().replaceWith(replacement)
        let newRoot2 = d.replaceWith(GreenToken(Word, "D"))

        // assert
        @Expect(newRoot.toString(), "a xyz d")
        @Expect(newRoot2.toString(), "a bc D")
        @Expect(root.text(), "a bc d")
        @Expect(refEq(newRoot.child(4).asNode().getOrThrow(), root.green.child(4).asNode().getOrThrow()))
    }
}
