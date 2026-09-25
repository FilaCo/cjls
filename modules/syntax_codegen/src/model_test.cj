package syntax_codegen

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

func kindsFile(): KindsFile {
    KindsFile(
        grammar: "",
        kindsOutput: "",
        kindsPackage: "",
        astOutput: "",
        astPackage: "",
        trivia: [KindEntry(name: "Ws")],
        punctuation: [
            KindEntry(name: "Plus", text: "+"),
            KindEntry(name: "Minus", text: "-"),
            KindEntry(name: "DotDot", text: ".."),
            KindEntry(name: "LBracket", text: "["),
            KindEntry(name: "RBracket", text: "]"),
            KindEntry(name: "Comma", text: ",")
        ],
        tokens: [KindEntry(name: "Int"), KindEntry(name: "Under", text: "_", word: true)],
        keywords: [KindEntry(name: "IfKw", text: "if"), KindEntry(name: "ElseKw", text: "else", contextual: true)],
        nodes: [KindEntry(name: "Error")]
    )
}

let EXPRS = """
    E = Lit | Bin | Idx | If | Range
    Lit = 'Int'
    Bin = lhs:E op:('+' | '-') rhs:E
    Idx = base:E '[' (E (',' E)*)? ']'
    If = 'if' E Lit ('else' (Lit | elseIf:If))?
    Range = start:E? '..' end:E?
    """

func modelOf(grammar: String): Model {
    buildModel(kindsFile(), parseGrammar(grammar))
}

func fieldsOf(model: Model, node: String): Array<String> {
    nodeIr(model, node).fields.map {
        f => match (f) {
            case NodeField(n, t, First) => "${n}: ${t} first"
            case NodeField(n, t, Nth(i, counted)) => "${n}: ${t} #${i} of ${counted.size}"
            case NodeField(n, t, All) => "${n}: ${t} all"
            case NodeField(n, t, AllFrom(i, counted)) => "${n}: ${t} all after ${i} of ${counted.size}"
            case TokenField(n, k) => "${n}: ${k}"
            case TokenSetField(n, ks) => "${n}: ${String.join(ks, delimiter: "|")}"
        }
    }
}

@Test
class ModelTest {
    @TestCase
    func tokensComeFirstThenTheNodesOfTheKindsFileThenThoseOfTheGrammar() {
        // act
        let sut = modelOf(EXPRS)

        // assert
        @Expect(sut.kinds.map {k => k.name},
            ["Ws", "Plus", "Minus", "DotDot", "LBracket", "RBracket", "Comma", "Int", "Under", "IfKw", "ElseKw", "Error",
                "Lit", "Bin", "Idx", "If", "Range"])
    }

    @TestCase
    func aRuleListingOnlyNodesIsAnEnumOfThem() {
        // act
        let sut = modelOf(EXPRS)

        // assert
        @Expect(sut.enums.map {e => e.name}, ["E"])
        @Expect(sut.enums[0].variants.map {v => "${v.name}(${v.typeName})"},
            ["AsLit(Lit)", "AsBin(Bin)", "AsIdx(Idx)", "AsIf(If)", "AsRange(Range)"])
        @Expect(sut.kindsOf("E"), ["Lit", "Bin", "Idx", "If", "Range"])
    }

    @TestCase
    func aLabelNamesTheVariant() {
        // act
        let sut = modelOf("S = Stmt:Lit | Other:Bin\nLit = 'Int'\nBin = Lit '+' Lit")

        // assert
        @Expect(sut.enums[0].variants.map {v => v.name}, ["Stmt", "Other"])
    }

    @TestCase
    func aVariantNamedLikeATypeIsRefused() {
        // act & assert
        @AssertThrows[GrammarException](modelOf("S = X | Y\nX = 'Int'\nY = 'Int'\nAsX = 'Int'"))
    }

    @TestCase
    func childrenOfOneTypeAreToldByTheirPositionAmongThoseThatCouldBeTakenForThem() {
        // act
        let sut = modelOf(EXPRS)

        // assert
        @Expect(fieldsOf(sut, "Bin"), ["lhs: E first", "op: Plus|Minus", "rhs: E #1 of 5"])
        @Expect(fieldsOf(sut, "Idx"),
            ["base: E first", "lBracketToken: LBracket", "es: E all after 1 of 5", "commaToken: Comma",
                "rBracketToken: RBracket"])
        // `Lit` is an `E` too: the second `Lit` is the second of them, after the condition
        @Expect(fieldsOf(sut, "If"),
            ["ifToken: IfKw", "e: E first", "lits: Lit all after 1 of 5", "elseToken: ElseKw", "elseIf: If #1 of 5"])
    }

    @TestCase
    func childrenAPositionCannotTellAreLeftToBeWrittenByHand() {
        // act
        let sut = nodeIr(modelOf(EXPRS), "Range")

        // assert
        @Expect(sut.handWritten, ["start", "end"])
        @Expect(fieldsOf(modelOf(EXPRS), "Range"), ["dotDotToken: DotDot"])
    }

    @TestCase
    func aReferenceToNothingDeclaredIsRefused() {
        // act & assert
        @AssertThrows[GrammarException](modelOf("A = B"))
        @AssertThrows[GrammarException](modelOf("A = '*'"))
    }

    @TestCase
    func anAccessorNamedLikeAMemberOfEveryViewOrAKeywordIsRefused() {
        // act & assert
        @AssertThrows[GrammarException](modelOf("A = syntax:B\nB = 'Int'"))
        @AssertThrows[GrammarException](modelOf("A = If\nIf = 'Int'"))
    }

    @TestCase
    func aTypeIsATy() {
        // act & assert
        @Expect(fieldsOf(modelOf("A = Type\nType = 'Int'"), "A"), ["ty: Type first"])
    }
}
