package syntax_codegen

import std.unittest.*
import std.unittest.testmacro.*

/**
 * A rule as ungrammar would write it back, with every group in parentheses.
 */
func show(rule: Rule): String {
    match (rule) {
        case NodeRef(n) => n
        case TokenRef(t) => "'${t}'"
        case Labeled(l, r) => "${l}:${show(r)}"
        case Seq(rs) => "(${String.join(rs.map {r => show(r)}, delimiter: " ")})"
        case Alt(rs) => "(${String.join(rs.map {r => show(r)}, delimiter: " | ")})"
        case Opt(r) => "${show(r)}?"
        case Rep(r) => "${show(r)}*"
    }
}

@Test
class UngrammarTest {
    @TestCase
    func rulesRunUpToTheNextRule() {
        // act
        let sut = parseGrammar("A = B 'x'\n  C?\nB = 'y'*\nC = 'z'")

        // assert
        @Expect(sut.rules.map {r => r.name}, ["A", "B", "C"])
        @Expect(show(sut.rules[0].rule), "(B 'x' C?)")
        @Expect(show(sut.rules[1].rule), "'y'*")
    }

    @TestCase
    func alternativesBindLooserThanSequencesAndALeadingBarIsAllowed() {
        // act
        let sut = parseGrammar("A =\n  | B 'x' | (C | 'y')* D")

        // assert
        @Expect(show(sut.rules[0].rule), "((B 'x') | ((C | 'y')* D))")
    }

    @TestCase
    func aLabelTakesTheAtomAfterItWithItsPostfix() {
        // act
        let sut = parseGrammar("A = lhs:E op:('+' | '-') rhs:E? items:E*")

        // assert
        @Expect(show(sut.rules[0].rule), "(lhs:E op:('+' | '-') rhs:E? items:E*)")
    }

    @TestCase
    func tokensMayEscapeQuotes() {
        // act
        let sut = parseGrammar(#"A = '\'' '\\'"#)

        // assert
        @Expect(show(sut.rules[0].rule), #"(''' '\')"#)
    }

    @TestCase
    func onlyCommentsOnLinesOfTheirOwnRightAboveARuleDocumentIt() {
        // act
        let sut = parseGrammar("// a file header\n\n// what A is\n// in two lines\nA = 'a'\nB = 'b' // trailing\nC = 'c'")

        // assert
        @Expect(sut.rules[0].doc, ["what A is", "in two lines"])
        @Expect(sut.rules[1].doc.size, 0)
        @Expect(sut.rules[2].doc.size, 0)
    }

    @TestCase
    func aSecondRuleOfOneNameIsRefused() {
        // act & assert
        @AssertThrows[GrammarException](parseGrammar("A = 'a'\nA = 'b'"))
    }

    @TestCase
    func anUnterminatedTokenIsRefused() {
        // act & assert
        @AssertThrows[GrammarException](parseGrammar("A = 'a\n"))
    }
}
