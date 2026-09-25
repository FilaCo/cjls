package cjsyntax.ast

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.*
import cjsyntax.{parse, SyntaxKind}

/**
 * The first node of `text` that is a `T`, the statements given in `main`.
 */
func first<T>(text: String): T where T <: AstNode<SyntaxKind, T> {
    let root = parse("main() {\n${text}\n}").syntaxNode()
    root.descendants().filterMap {n => T.cast(n)}.next().getOrThrow()
}

func texts<T>(items: Iterator<T>): Array<String> where T <: ToString {
    collectArray(items.map {i => i.toString()})
}

func text<T>(item: ?T): ?String where T <: ToString {
    item.map {i => i.toString()}
}

@Test
class AstTest {
    @TestCase
    func aBinaryExpressionHasItsSidesAndItsOperator() {
        // act
        let sut = first<BinExpr>("a + b * c")

        // assert
        @Expect(text(sut.lhs()), Some("a"))
        @Expect(sut.op().map {t => t.kind}, Some(SyntaxKind.Plus))
        @Expect(text(sut.rhs()), Some("b * c"))
    }

    @TestCase
    func anIfHasItsBranchesAndAnElseIf() {
        // act
        let sut = first<IfExpr>("if (a) { 1 } else if (b) { 2 } else { 3 }")
        let elseIf = sut.elseIf().getOrThrow()

        // assert
        @Expect(text(sut.condition()), Some("a"))
        @Expect(text(sut.then()), Some("{ 1 }"))
        @Expect(sut.elseBlock().isNone())
        @Expect(text(elseIf.condition()), Some("b"))
        @Expect(text(elseIf.elseBlock()), Some("{ 3 }"))
    }

    @TestCase
    func aConditionThatIsAnIfIsNotItsElseIf() {
        // act
        let sut = first<IfExpr>("if (if (a) { b } else { c }) { d }")

        // assert
        @Expect(text(sut.condition()), Some("if (a) { b } else { c }"))
        @Expect(sut.elseIf().isNone())
    }

    @TestCase
    func anIndexExpressionHasItsBaseAndIndices() {
        // act
        let sut = first<IndexExpr>("a[i, j]")

        // assert
        @Expect(text(sut.base()), Some("a"))
        @Expect(texts(sut.indices()), ["i", "j"])
    }

    @TestCase
    func aRangeHasWhicheverEndsItHas() {
        // act
        let full = first<RangeExpr>("a[1..=n : 2]")
        let endOnly = first<RangeExpr>("a[..n]")
        let startOnly = first<RangeExpr>("a[1..]")

        // assert
        @Expect([text(full.start()), text(full.end()), text(full.step())], [Some("1"), Some("n"), Some("2")])
        @Expect([text(endOnly.start()), text(endOnly.end())], [None, Some("n")])
        @Expect([text(startOnly.start()), text(startOnly.end())], [Some("1"), None])
        @Expect(full.op().map {t => t.kind}, Some(SyntaxKind.DotDotEq))
    }

    @TestCase
    func aFunctionTypeHasItsParametersAndItsReturnType() {
        // act
        let sut = first<FuncType>("let f: (Int64, String) -> Bool = g")

        // assert
        @Expect(texts(sut.types()), ["Int64", "String"])
        @Expect(text(sut.ret()), Some("Bool"))
    }

    @TestCase
    func aMatchCaseHasItsPatternsGuardAndBody() {
        // act
        let withSelector = first<MatchCase>("match (x) { case 1 | 2 where y => a; b }")
        let withoutSelector = first<MatchCase>("match { case x > 1 => a }")

        // assert
        @Expect(texts(withSelector.patterns()), ["1", "2"])
        @Expect(text(withSelector.guard()), Some("where y"))
        @Expect(withSelector.condition().isNone())
        @Expect(texts(withSelector.stmts()), ["a", "b"])
        @Expect(text(withoutSelector.condition()), Some("x > 1"))
        @Expect(texts(withoutSelector.stmts()), ["a"])
    }

    @TestCase
    func aSpawnHasItsContextAndItsLambda() {
        // act
        let withContext = first<SpawnExpr>("spawn (ctx) { => 1 }")
        let without = first<SpawnExpr>("spawn { => 2 }")

        // assert
        @Expect(text(withContext.context()), Some("ctx"))
        @Expect(text(withContext.lambda()), Some("{ => 1 }"))
        @Expect(without.context().isNone())
        @Expect(text(without.lambda()), Some("{ => 2 }"))
    }

    @TestCase
    func aFunctionHasItsNameParametersAndBody() {
        // act
        let root = parse("public func f<T>(a: Int64, b!: T = x): Unit where T <: A { a }").syntaxNode()
        let sut = SourceFile.cast(root).getOrThrow().decls().next().getOrThrow()

        // assert
        match (sut) {
            case AsFuncDecl(f) =>
                @Expect(text(f.name()), Some("f"))
                @Expect(f.modifiers().flatMap {m => m.publicToken()}.isSome())
                @Expect(texts(f.paramLists().next().getOrThrow().params()), ["a: Int64", "b!: T = x"])
                @Expect(text(f.retType().flatMap {r => r.ty()}), Some("Unit"))
                @Expect(text(f.block()), Some("{ a }"))
            case _ => @Expect(false)
        }
    }

    @TestCase
    func aStatementIsADeclarationOrAnExpression() {
        // act
        let sut = collectArray(first<IfExpr>("if (a) {\nlet x = 1\nx\n}").then().getOrThrow().stmts())

        // assert
        @Expect(sut.size, 2)
        @Expect(match (sut[0]) {
            case DeclStmt(AsVarDecl(_)) => true
            case _ => false
        })
        @Expect(match (sut[1]) {
            case ExprStmt(AsRefExpr(_)) => true
            case _ => false
        })
    }

    @TestCase
    func aViewCastsOnlyNodesOfItsKinds() {
        // arrange
        let lit = first<Literal>("1").syntax

        // act & assert
        @Expect(Literal.cast(lit).isSome())
        @Expect(BinExpr.cast(lit).isNone())
        @Expect(Expr.cast(lit).isSome())
        @Expect(Pattern.cast(lit).isNone())
        @Expect(Expr.cast(lit).getOrThrow().syntax == lit)
    }
}
