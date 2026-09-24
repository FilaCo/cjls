package cjsyntax

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

/**
 * `Kind "text"` per token, trivia but for newlines left out, then the errors.
 */
func lexDump(text: String): String {
    let lexed = tokenize(text)
    let sb = StringBuilder()
    for (i in 0..lexed.size) {
        let kind = lexed.kind(i)
        if (kind == Whitespace) {
            continue
        }
        if (sb.size > 0) {
            sb.append(" ")
        }
        sb.append("${kind}")
        if (kind.fixedText().isNone() && kind != Newline) {
            sb.append("(${lexed.tokenText(i)})")
        }
    }
    for (e in lexed.lexErrors()) {
        sb.append(" !${lexed.tokenText(e.tokenIndex)}: ${e.message}")
    }
    sb.toString()
}

@Test
class LexerTest {
    @TestCase
    func keywordsAreRecognisedAndOtherWordsAreNames() {
        // act & assert
        @Expect(lexDump("func main Int64 This this _ _x `class` 仓颉 x1"),
            "FuncKw MainKw Int64Kw ThisTypeKw ThisKw Underscore Ident(_x) Ident(`class`) Ident(仓颉) Ident(x1)")
    }

    @TestCase
    func numbersTakeTheirPrefixFractionExponentAndSuffix() {
        // act & assert
        @Expect(lexDump("0x1F 1_000u16 3.14 .5 1e-3f32 0x1p4 0b101 0o17 2i64"),
            "IntLit(0x1F) IntLit(1_000u16) FloatLit(3.14) FloatLit(.5) FloatLit(1e-3f32) FloatLit(0x1p4) " +
            "IntLit(0b101) IntLit(0o17) IntLit(2i64)")
    }

    @TestCase
    func aDotAfterANumberIsARangeOrAMemberUnlessADigitFollows() {
        // act & assert
        @Expect(lexDump("1..2 1..=2 1.foo"), "IntLit(1) DotDot IntLit(2) IntLit(1) DotDotEq IntLit(2) IntLit(1) Dot Ident(foo)")
    }

    @TestCase
    func aNumberRunningIntoLettersIsOneBadToken() {
        // act & assert
        @Expect(lexDump("12abc 1u7"),
            "IntLit(12abc) IntLit(1u7) !12abc: invalid suffix on a number !1u7: invalid suffix on a number")
    }

    @TestCase
    func aStringIsCutAroundItsInterpolations() {
        // act & assert
        @Expect(lexDump(#""a${x + "b"}c""#),
            "StringStart(\") StringContent(a) InterpolationStart Ident(x) Plus StringStart(\") StringContent(b) " +
            "StringEnd(\") InterpolationEnd StringContent(c) StringEnd(\")")
    }

    @TestCase
    func bracesInsideAnInterpolationDoNotEndIt() {
        // act & assert
        @Expect(lexDump(#"'${ {a} }'"#),
            "StringStart(') InterpolationStart LBrace Ident(a) RBrace InterpolationEnd StringEnd(')")
    }

    @TestCase
    func escapesStayInTheContent() {
        // act & assert
        @Expect(lexDump(#""\"\${x}\u{41}""#), #"StringStart(") StringContent(\"\${x}\u{41}) StringEnd(")"#)
    }

    @TestCase
    func aMultilineStringSpansLines() {
        // act & assert
        @Expect(lexDump("\"\"\"\nline \"one\"\n\${2}\"\"\""),
            "StringStart(\"\"\") StringContent(\nline \"one\"\n) InterpolationStart IntLit(2) InterpolationEnd StringEnd(\"\"\")")
    }

    @TestCase
    func aSingleLineStringEndsAtTheLineUnterminated() {
        // act & assert
        @Expect(lexDump("\"abc\nx"), "StringStart(\") StringContent(abc) Newline Ident(x) !abc: unterminated string")
        @Expect(lexDump("J\"a\""), "StringStart(J\") StringContent(a) StringEnd(\")")
    }

    @TestCase
    func rawStringsEndAtTheirOwnNumberOfHashes() {
        // act & assert
        @Expect(lexDump("#\"a\"b\"# ##'x'#'## # x"), "RawStringLit(#\"a\"b\"#) RawStringLit(##'x'#'##) Hash Ident(x)")
        @Expect(lexDump("#\"abc"), "RawStringLit(#\"abc) !#\"abc: unterminated raw string")
    }

    @TestCase
    func runeAndByteLiteralsHoldOneCharacterOrEscape() {
        // act & assert
        @Expect(lexDump("r'a' r\"\\n\" r'\\u{4F60}' b'x' r'仓'"),
            "RuneLit(r'a') RuneLit(r\"\\n\") RuneLit(r'\\u{4F60}') ByteLit(b'x') RuneLit(r'仓')")
        @Expect(lexDump("r'ab'"), "RuneLit(r'ab') !r'ab': a character literal holds one character")
    }

    @TestCase
    func blockCommentsNest() {
        // act & assert
        @Expect(lexDump("/* a /* b */ c */x // end"), "BlockComment(/* a /* b */ c */) Ident(x) LineComment(// end)")
        @Expect(lexDump("/* open"), "BlockComment(/* open) !/* open: unterminated block comment")
    }

    @TestCase
    func greaterThanAndQuestionAreAlwaysCutAlone() {
        // act & assert
        @Expect(lexDump(">>= >= ?? =>"), "Gt Gt Eq Gt Eq Question Question FatArrow")
    }

    @TestCase
    func punctuationTakesTheLongestMatch() {
        // act & assert
        @Expect(lexDump("... ..= ** **= <<= <: <- -> |> ~> @! :: && &&= \\"),
            "DotDotDot DotDotEq StarStar StarStarEq LtLtEq LtColon LArrow Arrow PipeGt TildeGt AtBang ColonColon " +
            "AmpAmp AmpAmpEq Backslash")
    }

    @TestCase
    func dollarNamesAreOneToken() {
        // act & assert
        @Expect(lexDump(#"$x $`y` $(z)"#), #"DollarIdent($x) DollarIdent($`y`) Dollar LParen Ident(z) RParen"#)
    }

    @TestCase
    func linesBreaksOfEitherKindAreNewlines() {
        // act & assert
        @Expect(lexDump("a\r\n\nb\rc"), "Ident(a) Newline Ident(b) ErrorToken(\r) Ident(c) !\r: unknown character")
    }

    @TestCase[text in [
        #"func f<T>(a!: Int64 = 1): T where T <: ToString { "${a}" }"#,
        #""unterminated ${ x"#,
        "\"\"\"\n\${ \"\"\" \n \${1} \"\"\" }\n\"\"\"",
        "let s = #'raw'# + r'c' + b'x'",
        "0x 1e 1.e3 `` ` a\n",
        #"@M[x](a) quote($x \( ) /*/"#,
        "\u{3000}仓颉 \u{1F600}"
    ]]
    func theTokensCoverTheTextExactly(text: String) {
        // act
        let lexed = tokenize(text)

        // assert
        let sb = StringBuilder()
        for (i in 0..lexed.size) {
            sb.append(lexed.tokenText(i))
        }
        @Expect(sb.toString(), text)
        @Expect(lexed.covered, text.size)
    }
}
