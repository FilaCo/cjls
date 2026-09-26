package loupe

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.TextRange
import rope.Rope
import cjsyntax.CjSyntaxElement
import cjsyntax.parse as parseText
import loupe.vfs.FileId
import loupe.db.AnalysisDatabase

func highlightOf(text: String, range!: ?TextRange = None): Array<HighlightedRange> {
    let db = AnalysisDatabase()
    db.setFileText(FileId(0), Rope(text))
    highlight(db, FileId(0), range: range)
}

/**
 * The highlighting as `tag[modifiers]@range text`, a token each.
 */
func highlighted(text: String, range!: ?TextRange = None): Array<String> {
    let bytes = text.toArray()
    highlightOf(text, range: range).map {it => "${it} ${String.fromUtf8(bytes[it.range.start..it.range.end])}"}
}

@Test
class HighlightTest {
    @TestCase
    func keywordsLiteralsCommentsAndOperatorsAreToldByTheirKind() {
        // act
        let result = highlighted("/* c */ var b = a >> 2 ?? 1.5 >= r'c' && true")

        // assert - `>>`, `??` and `>=` are glued by the parser, one token each; `a` is a name used
        @Expect(result, [
            "Comment[Documentation]@0..7 /* c */",
            "Keyword@8..11 var",
            "Variable[Declaration]@12..13 b",
            "Operator@14..15 =",
            "Operator@18..20 >>",
            "NumberLiteral@21..22 2",
            "Operator@23..25 ??",
            "NumberLiteral@26..29 1.5",
            "Operator@30..32 >=",
            "StringLiteral@33..37 r'c'",
            "Operator@38..40 &&",
            "Keyword@41..45 true"
        ])
    }

    @TestCase
    func declarationsAreToldWhatTheyDeclareWithTheirModifiers() {
        // act
        let result = highlighted("class A<T> {\n    static let x: Int64 = 1\n    A(let y: Int64, z: Bool) {}\n    prop p: T { get() { x } }\n    operator func +(o: A<T>): A<T> { this }\n}\nconst K = 1")

        // assert - `x` in the getter is a use, not told yet
        @Expect(result, [
            "Keyword@0..5 class",
            "Class[Declaration]@6..7 A",
            "TypeParameter[Declaration]@8..9 T",
            "Keyword@17..23 static",
            "Keyword@24..27 let",
            "Field[Declaration, Readonly, Static]@28..29 x",
            "BuiltinType[DefaultLibrary]@31..36 Int64",
            "Operator@37..38 =",
            "NumberLiteral@39..40 1",
            "Constructor[Declaration]@45..46 A",
            "Keyword@47..50 let",
            "Field[Declaration, Readonly]@51..52 y",
            "BuiltinType[DefaultLibrary]@54..59 Int64",
            "Parameter[Declaration]@61..62 z",
            "BuiltinType[DefaultLibrary]@64..68 Bool",
            "Keyword@77..81 prop",
            "Property[Declaration]@82..83 p",
            "TypeName@85..86 T",
            "Keyword@89..92 get",
            "Keyword@107..115 operator",
            "Keyword@116..120 func",
            "Method[Declaration]@121..122 +",
            "Parameter[Declaration]@123..124 o",
            "TypeName@126..127 A",
            "TypeName@128..129 T",
            "TypeName@133..134 A",
            "TypeName@135..136 T",
            "Keyword@140..144 this",
            "Keyword@149..154 const",
            "Constant[Declaration, Readonly]@155..156 K",
            "Operator@157..158 =",
            "NumberLiteral@159..160 1"
        ])
    }

    @TestCase
    func aContextualKeywordIsAKeywordOnlyWhereItIsNoName() {
        // act
        let result = highlighted("public class open {}")

        // assert
        @Expect(result, ["Keyword@0..6 public", "Keyword@7..12 class", "Class[Declaration]@13..17 open"])
    }

    @TestCase
    func aCommentAttachedToADeclarationDocumentsIt() {
        // act
        let result = highlighted("// doc\nfunc f() {}\n\n// loose\n\nfunc g() {}")

        // assert
        @Expect(result, [
            "Comment[Documentation]@0..6 // doc",
            "Keyword@7..11 func",
            "Function[Declaration]@12..13 f",
            "Comment@20..28 // loose",
            "Keyword@30..34 func",
            "Function[Declaration]@35..36 g"
        ])
    }

    @TestCase
    func anInterpolatedStringIsSplitAroundItsCode() {
        // act
        let result = highlighted(##"let s = "a${n + 1}b""##)

        // assert - the `${` and `}` around the code are left out, as other punctuation
        @Expect(result, [
            "Keyword@0..3 let",
            "Variable[Declaration, Readonly]@4..5 s",
            "Operator@6..7 =",
            "StringLiteral@8..9 \"",
            "StringLiteral@9..10 a",
            "Operator@14..15 +",
            "NumberLiteral@16..17 1",
            "StringLiteral@18..19 b",
            "StringLiteral@19..20 \""
        ])
    }

    @TestCase
    func builtinAnnotationsAreToldFromMacroCalls() {
        // act
        let result = highlighted("@Deprecated\nfunc f() {}\n@M class A {}")

        // assert
        @Expect(result, [
            "BuiltinAnnotation@0..1 @",
            "BuiltinAnnotation@1..11 Deprecated",
            "Keyword@12..16 func",
            "Function[Declaration, Deprecated]@17..18 f",
            "MacroCall@24..25 @",
            "MacroCall@25..26 M",
            "Keyword@27..32 class",
            "Class[Declaration]@33..34 A"
        ])
    }

    @TestCase
    func aNameAPatternBindsIsADeclarationUnlessItMayBeAConstructor() {
        // act
        let result = highlighted(
            "main() { for ((i, _) in xs) { match (e) { case R => 0 case G(n) => n case q: E => 1 } }; f {a => a} }")

        // assert - `R` and `n` may be enum constructors, which only names resolved tell
        @Expect(result, [
            "Keyword@0..4 main",
            "Keyword@9..12 for",
            "Variable[Declaration]@15..16 i",
            "Keyword@21..23 in",
            "Keyword@30..35 match",
            "Keyword@42..46 case",
            "Operator@49..51 =>",
            "NumberLiteral@52..53 0",
            "Keyword@54..58 case",
            "Operator@64..66 =>",
            "Keyword@69..73 case",
            "Variable[Declaration]@74..75 q",
            "TypeName@77..78 E",
            "Operator@79..81 =>",
            "NumberLiteral@82..83 1",
            "Parameter[Declaration]@92..93 a",
            "Operator@94..96 =>"
        ])
    }

    @TestCase
    func whatSitsInAnErrorNodeIsToldByItsKindAlone() {
        // act
        let result = highlighted("func f() {}\n) foo let + 1")

        // assert - `foo` would take a context to tell
        @Expect(result, [
            "Keyword@0..4 func",
            "Function[Declaration]@5..6 f",
            "Keyword@18..21 let",
            "Operator@22..23 +",
            "NumberLiteral@24..25 1"
        ])
    }

    @TestCase
    func aRangeGivesOnlyTheTokensItIntersects() {
        // act - from inside `let` to inside `xy`
        let result = highlighted("var a = 1\nlet xy = 2\nvar b = 3", range: TextRange(11, 15))

        // assert
        @Expect(result, ["Keyword@10..13 let", "Variable[Declaration, Readonly]@14..16 xy"])
    }

    @TestCase
    func eachTokenIsHighlightedOnceInTheOrderOfTheText() {
        // arrange
        let text = ##"""
            /** doc */
            @Deprecated
            public class A<T> <: I & J where T <: K {
                A(let x: ?Array<T>, y!: Int64 = 0) {}
                static func f(a: (Int64) -> Unit): Unit { let s = "${a}${ "${x}" }"; @M(s) }
            }
            enum E { | R | G(Int64) }
            main() { match (E.R) { case G(n) => n; case _ => 1 } }
            ) garbage
            """##
        let tokens = HashSet<TextRange>()
        for (element in parseText(text).syntaxNode().descendantsWithTokens()) {
            match (element) {
                case CjSyntaxElement.Token(token) => tokens.add(token.textRange)
                case _ => ()
            }
        }

        // act
        let result = highlightOf(text)

        // assert
        @Expect(result.size > 40)
        for (i in 0..result.size) {
            @Expect(tokens.contains(result[i].range))
            if (i > 0) {
                @Expect(result[i - 1].range.end <= result[i].range.start)
            }
        }
    }

    @TestCase
    func aFileNeverSetHasNoHighlighting() {
        // act, assert
        @Expect(highlight(AnalysisDatabase(), FileId(7)).size, 0)
    }
}
