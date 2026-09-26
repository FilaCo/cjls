package ginkgo.parsing

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.*

@Test
class ParserTest {
    @TestCase
    func precedingMarkersBuildOperatorTrees() {
        // act
        let parse = toyParse("1+2*3")

        // assert
        @Expect(parse.errors.size, 0)
        @Expect(parse.syntaxNode().debugDump(), "Root@0..5\n" +
            "  Line@0..5\n" +
            "    Bin@0..5\n" +
            "      Lit@0..1\n" +
            "        Num@0..1 \"1\"\n" +
            "      Plus@1..2 \"+\"\n" +
            "      Bin@2..5\n" +
            "        Lit@2..3\n" +
            "          Num@2..3 \"2\"\n" +
            "        Star@3..4 \"*\"\n" +
            "        Lit@4..5\n" +
            "          Num@4..5 \"3\"\n")
    }

    @TestCase
    func triviaGoesBetweenNodesAndTrailingTriviaToTheRoot() {
        // act
        let parse = toyParse(" 1 + 2 \n")

        // assert
        @Expect(parse.syntaxNode().debugDump(), "Root@0..8\n" +
            "  Ws@0..1 \" \"\n" +
            "  Line@1..6\n" +
            "    Bin@1..6\n" +
            "      Lit@1..2\n" +
            "        Num@1..2 \"1\"\n" +
            "      Ws@2..3 \" \"\n" +
            "      Plus@3..4 \"+\"\n" +
            "      Ws@4..5 \" \"\n" +
            "      Lit@5..6\n" +
            "        Num@5..6 \"2\"\n" +
            "  Ws@6..7 \" \"\n" +
            "  Newline@7..8 \"\\n\"\n")
    }

    @TestCase
    func attachedTriviaGoesInsideTheNode() {
        // act
        let parse = toyParse("1\n\n# two\n2")
        let lines = collectArray(parse.syntaxNode().children())

        // assert
        @Expect(lines.size, 2)
        @Expect(lines[1].text(), "# two\n2")
        @Expect(lines[1].firstToken().getOrThrow().kind, Comment)
    }

    @TestCase
    func aCompositeTokenIsMadeOnlyOfJointPieces() {
        // act
        let joint = toyParse("1>>2")
        let apart = toyParse("1> >2")

        // assert
        @Expect(joint.errors.size, 0)
        let shr = joint.syntaxNode().descendantsWithTokens().filter {el => el.kind == Shr}.next().getOrThrow()
        @Expect(shr.toString(), ">>")
        @Expect(apart.errors.size > 0)
        @Expect(apart.syntaxNode().text(), "1> >2")
    }

    @TestCase
    func errorsAreReportedAndTheTextIsKeptWhole() {
        // arrange
        let text = "1 + ? 2\n* 3"

        // act
        let parse = toyParse(text)

        // assert
        @Expect(parse.syntaxNode().text(), text)
        let messages = parse.errors.map {e => e.toString()}
        @Expect(String.join(messages, delimiter: "; "),
            "4..4: expected a number; 4..5: unknown character; 6..6: expected a newline; 8..8: expected a number; " +
                "10..10: expected a newline")
        @Expect(parse.syntaxNode().descendants().filter {n => n.kind == ErrorNode}.count(), 4)
    }

    @TestCase
    func newlinesBeforeTokensAreSeen() {
        // arrange
        let lexed = toyLex("1 #c\n+2")

        // act
        let input = toyInput(lexed)

        // assert
        @Expect(input.size, 3)
        @Expect(!input.isNewlineBefore(0))
        @Expect(input.isNewlineBefore(1))
        @Expect(!input.isNewlineBefore(2))
        @Expect(!input.isJointWithNext(0))
        @Expect(input.isJointWithNext(1))
    }

    @TestCase
    func rewindForgetsWhatWasParsedSince() {
        // arrange
        let lexed = toyLex("1+2")
        let p = toyParser(lexed)
        let root = p.start()
        let snapshot = p.snapshot()
        toyExpr(p, 0)
        p.error("changed my mind")

        // act
        let erred = p.hasErrorSince(snapshot)
        p.rewind(snapshot)
        p.bumpAny()
        p.bumpAny()
        p.bumpAny()
        root.complete(p, Root)
        let parse = buildTree(lexed, p, ToyTrivia())

        // assert
        @Expect(erred)
        @Expect(parse.errors.size, 0)
        @Expect(parse.syntaxNode().debugDump(), "Root@0..3\n  Num@0..1 \"1\"\n  Plus@1..2 \"+\"\n  Num@2..3 \"2\"\n")
    }

    @TestCase
    func whatTheParserLeavesGoesInAnErrorNodeAtTheEnd() {
        // arrange
        let lexed = toyLex("1 2")
        let p = toyParser(lexed)
        let root = p.start()
        p.bump(Num)
        root.complete(p, Root)

        // act
        let parse = buildTree(lexed, p, ToyTrivia())

        // assert
        @Expect(parse.syntaxNode().text(), "1 2")
        @Expect(parse.errors.size, 1)
        @Expect(parse.syntaxNode().lastChild().getOrThrow().kind, ErrorNode)
    }

    @TestCase
    func expectReportsTheMissingKindAsData() {
        // arrange
        let lexed = toyLex("1")
        let p = toyParser(lexed)
        let root = p.start()
        p.bump(Num)
        p.expect(Plus)
        root.complete(p, Root)

        // act
        let parse = buildTree(lexed, p, ToyTrivia())

        // assert
        @Expect(parse.errors, [SyntaxError(ParseError.Expected(Plus), TextRange.empty(1))])
    }

    @TestCase
    func aParserThatMakesNoProgressThrows() {
        // arrange
        let p = toyParser(toyLex("1"))

        // act & assert
        @AssertThrows[IllegalStateException]({
            while (!p.at(Plus)) {}
        })
    }

    @TestCase
    func parsesOfOneTextAreEqual() {
        // act, assert
        @Expect(toyParse("1 + 2") == toyParse("1 + 2"))
        @Expect(toyParse("1 + 2") != toyParse("1 + 3"))
        @Expect(toyParse("1 +") != toyParse("1 + 2"))
    }
}
