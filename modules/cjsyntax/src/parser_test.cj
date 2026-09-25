package cjsyntax

import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.*

/**
 * The tree as nested `(Kind children)`, tokens as their text, trivia left out; then the errors.
 */
func sexp(text: String): String {
    let parse = parse(text)
    let sb = StringBuilder()
    writeSexp(sb, parse.syntaxNode())
    for (e in parse.errors) {
        sb.append(" !${e}")
    }
    sb.toString()
}

func writeSexp(sb: StringBuilder, node: SyntaxNode<SyntaxKind>): Unit {
    sb.append("(${node.kind}")
    for (child in node.childrenWithTokens()) {
        match (child) {
            case SyntaxElement.Node(n) =>
                sb.append(" ")
                writeSexp(sb, n)
            case SyntaxElement.Token(t) where !t.kind.isTrivia() =>
                sb.append(" ")
                sb.append(t.text())
            case _ => ()
        }
    }
    sb.append(")")
}

/**
 * The tree of `text` as statements in `main`, without the `main`, which shifts error offsets by 9.
 */
func stmtSexp(text: String): String {
    let full = sexp("main() {\n${text}\n}")
    let prefix = "(SourceFile (MainDecl main (ParamList ( )) (Block { "
    let body = if (full.startsWith(prefix)) { full[prefix.size..] } else { full }
    let end = body.indexOf(" })))") ?? return body
    body[..end] + body[end + 5..]
}

/**
 * Snapshot tests: each pair is a text and its tree as `sexp` shows it, errors included. Each was checked against
 * the compiler's parser (`cangjie_compiler/src/Parse`) when written.
 */
@Test
class StatementParseTest {
    let cases: Array<(String, String)> = [
        ("a = b + c * d ** e ** f", "(BinExpr (RefExpr (NameRef a)) = (BinExpr (RefExpr (NameRef b)) + (BinExpr (RefExpr (NameRef c)) * (BinExpr (RefExpr (NameRef d)) ** (BinExpr (RefExpr (NameRef e)) ** (RefExpr (NameRef f)))))))"),
        ("a = b = c", "(BinExpr (BinExpr (RefExpr (NameRef a)) = (RefExpr (NameRef b))) = (RefExpr (NameRef c))) !14..14: assignment operators cannot be chained"),
        ("a < b < c", "(BinExpr (BinExpr (RefExpr (NameRef a)) < (RefExpr (NameRef b))) < (RefExpr (NameRef c))) !14..14: comparison operators cannot be chained"),
        ("x is Int64 && y as String", "(BinExpr (IsExpr (RefExpr (NameRef x)) is (PrimType Int64)) && (AsExpr (RefExpr (NameRef y)) as (PathType (PathSegment (NameRef String)))))"),
        ("a |> f ~> g", "(BinExpr (BinExpr (RefExpr (NameRef a)) |> (RefExpr (NameRef f))) ~> (RefExpr (NameRef g)))"),
        ("a >>= 1; b >= c; d > e", "(BinExpr (RefExpr (NameRef a)) >>= (Literal 1)) ; (BinExpr (RefExpr (NameRef b)) >= (RefExpr (NameRef c))) ; (BinExpr (RefExpr (NameRef d)) > (RefExpr (NameRef e)))"),
        ("a\n+ b", "(BinExpr (RefExpr (NameRef a)) + (RefExpr (NameRef b)))"),
        ("a\n-1", "(RefExpr (NameRef a)) (UnaryExpr - (Literal 1))"),
        ("a\n.b", "(MemberAccessExpr (RefExpr (NameRef a)) . (NameRef b))"),
        ("f\n(x)", "(RefExpr (NameRef f)) (ParenExpr ( (RefExpr (NameRef x)) ))"),
        ("x?.y?[0]", "(IndexExpr (OptionalExpr (MemberAccessExpr (OptionalExpr (RefExpr (NameRef x)) ?) . (NameRef y)) ?) [ (Literal 0) ])"),
        ("x++", "(PostfixExpr (RefExpr (NameRef x)) ++)"),
        ("-a.b(c)[d]", "(UnaryExpr - (IndexExpr (CallExpr (MemberAccessExpr (RefExpr (NameRef a)) . (NameRef b)) (ArgList ( (Arg (RefExpr (NameRef c))) ))) [ (RefExpr (NameRef d)) ]))"),
        ("if (a) { 1 }\nelse { 2 }", "(IfExpr if ( (RefExpr (NameRef a)) ) (Block { (Literal 1) }) else (Block { (Literal 2) }))"),
        ("(a, b)", "(TupleExpr ( (RefExpr (NameRef a)) , (RefExpr (NameRef b)) ))"),
        ("()", "(UnitExpr ( ))"),
        ("[1, 2,]", "(ArrayExpr [ (Literal 1) , (Literal 2) , ])"),
        ("f(a<b, c>(d))", "(CallExpr (RefExpr (NameRef f)) (ArgList ( (Arg (CallExpr (RefExpr (NameRef a) (TypeArgList < (PathType (PathSegment (NameRef b))) , (PathType (PathSegment (NameRef c))) >)) (ArgList ( (Arg (RefExpr (NameRef d))) )))) )))"),
        ("f(a < b, c > d)", "(CallExpr (RefExpr (NameRef f)) (ArgList ( (Arg (BinExpr (RefExpr (NameRef a)) < (RefExpr (NameRef b)))) , (Arg (BinExpr (RefExpr (NameRef c)) > (RefExpr (NameRef d)))) )))"),
        ("(a < b, (c, d), e > f)", "(TupleExpr ( (BinExpr (RefExpr (NameRef a)) < (RefExpr (NameRef b))) , (TupleExpr ( (RefExpr (NameRef c)) , (RefExpr (NameRef d)) )) , (BinExpr (RefExpr (NameRef e)) > (RefExpr (NameRef f))) ))"),
        ("Array<Array<Int64>>()", "(CallExpr (RefExpr (NameRef Array) (TypeArgList < (PathType (PathSegment (NameRef Array) (TypeArgList < (PrimType Int64) >))) >)) (ArgList ( )))"),
        ("Int64(x) + Int64.Max", "(BinExpr (TypeConvExpr (PrimType Int64) ( (RefExpr (NameRef x)) )) + (MemberAccessExpr (PrimTypeExpr Int64) . (NameRef Max)))"),
        ("VArray<Int64, \$3>(repeat: 0)", "(VArrayExpr (VArrayType VArray < (PrimType Int64) , \$ 3 >) (ArgList ( (Arg (NameRef repeat) : (Literal 0)) )))"),
        ("{ => 1 }", "(LambdaExpr { => (Literal 1) })"),
        ("{ a: Int64, _ => a }", "(LambdaExpr { (LambdaParamList (LambdaParam (Name a) : (PrimType Int64)) , (LambdaParam _)) => (RefExpr (NameRef a)) })"),
        ("{ a }", "(LambdaExpr { (RefExpr (NameRef a)) }) !10..10: expected '=>' in a lambda"),
        ("f(1) { x => x }", "(TrailingLambdaExpr (CallExpr (RefExpr (NameRef f)) (ArgList ( (Arg (Literal 1)) ))) (LambdaExpr { (LambdaParamList (LambdaParam (Name x))) => (RefExpr (NameRef x)) }))"),
        ("f { i }", "(TrailingLambdaExpr (RefExpr (NameRef f)) (LambdaExpr { (RefExpr (NameRef i)) }))"),
        ("if (let Some(x) <- a && x > 0) {} else if (b) {} else {}", "(IfExpr if ( (BinExpr (LetExpr let (EnumPat (PathSegment (NameRef Some)) ( (BindPat (Name x)) )) <- (RefExpr (NameRef a))) && (BinExpr (RefExpr (NameRef x)) > (Literal 0))) ) (Block { }) else (IfExpr if ( (RefExpr (NameRef b)) ) (Block { }) else (Block { })))"),
        ("while (let Some(v) <- it.next()) {}", "(WhileExpr while ( (LetExpr let (EnumPat (PathSegment (NameRef Some)) ( (BindPat (Name v)) )) <- (CallExpr (MemberAccessExpr (RefExpr (NameRef it)) . (NameRef next)) (ArgList ( )))) ) (Block { }))"),
        ("match (x) {\ncase 1 | 2 => a\ncase Some(y) where y > 0 => b; c\ncase E.A(_, (p, q)) => ()\ncase n: Int64 => n\ncase _ => 0\n}", "(MatchExpr match ( (RefExpr (NameRef x)) ) (MatchBody { (MatchCase case (LiteralPat 1) | (LiteralPat 2) => (RefExpr (NameRef a))) (MatchCase case (EnumPat (PathSegment (NameRef Some)) ( (BindPat (Name y)) )) (Guard where (BinExpr (RefExpr (NameRef y)) > (Literal 0))) => (RefExpr (NameRef b)) ; (RefExpr (NameRef c))) (MatchCase case (EnumPat (PathSegment (NameRef E)) . (PathSegment (NameRef A)) ( (WildcardPat _) , (TuplePat ( (BindPat (Name p)) , (BindPat (Name q)) )) )) => (UnitExpr ( ))) (MatchCase case (TypePat (Name n) : (PrimType Int64)) => (RefExpr (NameRef n))) (MatchCase case (WildcardPat _) => (Literal 0)) }))"),
        ("match {\ncase x > 0 => 1\ncase _ => 2\n}", "(MatchExpr match (MatchBody { (MatchCase case (BinExpr (RefExpr (NameRef x)) > (Literal 0)) => (Literal 1)) (MatchCase case (WildcardExpr _) => (Literal 2)) }))"),
        ("match (x) { case 1 => }", "(MatchExpr match ( (RefExpr (NameRef x)) ) (MatchBody { (MatchCase case (LiteralPat 1) =>) })) !30..30: a match case cannot be empty"),
        ("try (r = open()) { use(r) } catch (e: A | B) { } catch (_) { } finally { close() }", "(TryExpr try (ResourceList ( (ResourceDecl (Name r) = (CallExpr (RefExpr (NameRef open)) (ArgList ( )))) )) (Block { (CallExpr (RefExpr (NameRef use)) (ArgList ( (Arg (RefExpr (NameRef r))) ))) }) (CatchClause catch ( (CatchPat (Name e) : (PathType (PathSegment (NameRef A))) | (PathType (PathSegment (NameRef B)))) ) (Block { })) (CatchClause catch ( (CatchPat _) ) (Block { })) (FinallyClause finally (Block { (CallExpr (RefExpr (NameRef close)) (ArgList ( ))) })))"),
        ("for ((k, v) in map where k > 0) { }", "(ForInExpr for ( (TuplePat ( (BindPat (Name k)) , (BindPat (Name v)) )) in (RefExpr (NameRef map)) (Guard where (BinExpr (RefExpr (NameRef k)) > (Literal 0))) ) (Block { }))"),
        ("do { i++ } while (i < 10)", "(DoWhileExpr do (Block { (PostfixExpr (RefExpr (NameRef i)) ++) }) while ( (BinExpr (RefExpr (NameRef i)) < (Literal 10)) ))"),
        ("spawn { work() }", "(SpawnExpr spawn (LambdaExpr { (CallExpr (RefExpr (NameRef work)) (ArgList ( ))) }))"),
        ("synchronized (m) { x }", "(SynchronizedExpr synchronized ( (RefExpr (NameRef m)) ) (Block { (RefExpr (NameRef x)) }))"),
        ("unsafe { f() }", "(UnsafeExpr unsafe (Block { (CallExpr (RefExpr (NameRef f)) (ArgList ( ))) }))"),
        ("return", "(ReturnExpr return)"),
        ("return 1", "(ReturnExpr return (Literal 1))"),
        ("throw E()", "(ThrowExpr throw (CallExpr (RefExpr (NameRef E)) (ArgList ( ))))"),
        ("break; continue", "(BreakExpr break) ; (ContinueExpr continue)"),
        ("\"a\${b}c\${\"d\${e}\"}\"", "(StringLit \" a (Interpolation \${ (RefExpr (NameRef b)) }) c (Interpolation \${ (StringLit \" d (Interpolation \${ (RefExpr (NameRef e)) }) \") }) \")"),
        ("quote(a + \$b + \$(c) \\( )", "(QuoteExpr quote ( a + \$b + (QuoteInterpolation \$ ( (RefExpr (NameRef c)) )) \\ ( ))"),
        ("@M(1, 2)", "(MacroExpandExpr @ (NameRef M) (MacroArgs ( 1 , 2 )))"),
        ("@M[x] var y = 1", "(MacroExpandDecl @ (NameRef M) (MacroAttr [ x ]) (VarDecl var (Name y) = (Literal 1)))"),
        ("@OverflowWrapping { => a + b }", "(LambdaExpr (Annotation @ (NameRef OverflowWrapping)) { => (BinExpr (RefExpr (NameRef a)) + (RefExpr (NameRef b))) })"),
        ("let (a, b) = t", "(VarDecl let (TuplePat ( (BindPat (Name a)) , (BindPat (Name b)) )) = (RefExpr (NameRef t)))"),
        ("const y = 1", "(VarDecl (Modifiers const) (Name y) = (Literal 1))"),
        ("func local<T>(t: T): T { t }", "(FuncDecl func (Name local) (TypeParamList < (TypeParam (Name T)) >) (ParamList ( (Param (Name t) : (PathType (PathSegment (NameRef T)))) )) (RetType : (PathType (PathSegment (NameRef T)))) (Block { (RefExpr (NameRef t)) }))"),
        ("public = 1", "(BinExpr (RefExpr (NameRef public)) = (Literal 1))"),
        ("x.y<Int64>(1)", "(CallExpr (MemberAccessExpr (RefExpr (NameRef x)) . (NameRef y) (TypeArgList < (PrimType Int64) >)) (ArgList ( (Arg (Literal 1)) )))"),
        ("e[1..]", "(IndexExpr (RefExpr (NameRef e)) [ (RangeExpr (Literal 1) ..) ])"),
        ("e[..=2 : 1]", "(IndexExpr (RefExpr (NameRef e)) [ (RangeExpr ..= (Literal 2) : (Literal 1)) ])"),
        ("_ = f()", "(BinExpr (WildcardExpr _) = (CallExpr (RefExpr (NameRef f)) (ArgList ( ))))"),
        ("class Local {}", "(ClassDecl class (Name Local) (DeclBody { })) !9..9: unexpected class declaration in a block"),
        ("f(,)", "(CallExpr (RefExpr (NameRef f)) (ArgList ( (Arg) , ))) !11..11: expected an expression"),
        ("let x = )", "(VarDecl let (Name x) =) (ErrorNode )) !16..16: expected an expression !16..16: expected a newline or ';' !17..17: expected an expression or a declaration"),
    ]

    @TestCase
    func eachStatementParsesToItsTree() {
        for ((text, expected) in cases) {
            @Expect(stmtSexp(text), expected)
        }
    }
}

@Test
class DeclarationParseTest {
    let cases: Array<(String, String)> = [
        ("package a.b.c", "(SourceFile (PackageHeader package (NameRef a) . (NameRef b) . (NameRef c)))"),
        ("macro package m", "(SourceFile (PackageHeader macro package (NameRef m)))"),
        ("import a.b.*\nimport a.{b, c as d, e.*}\nimport org::{x.y}\npublic import p.q", "(SourceFile (ImportDecl import (ImportTree (NameRef a) . (NameRef b) . *)) (ImportDecl import (ImportTree (NameRef a) . (ImportTreeList { (ImportTree (NameRef b)) , (ImportTree (NameRef c) (ImportAlias as (Name d))) , (ImportTree (NameRef e) . *) }))) (ImportDecl import (ImportTree (NameRef org) :: (ImportTreeList { (ImportTree (NameRef x) . (NameRef y)) }))) (ImportDecl (Modifiers public) import (ImportTree (NameRef p) . (NameRef q))))"),
        ("import a.* as b", "(SourceFile (ImportDecl import (ImportTree (NameRef a) . * (ImportAlias as (Name b))))) !10..10: only a single import can be renamed"),
        ("public open class A<T> <: B<T> & C where T <: D & E {\n    public var x: Int64 = 1\n    A(let y: T, z!: Int64 = 2) {}\n    init() {}\n    ~init() {}\n    public mut prop p: Int64 {\n        get() { x }\n        set(v) { x = v }\n    }\n    public operator func [](i: Int64): T { y }\n    operator func >>(o: A<T>): A<T> { this }\n    func abstractOne(): Unit\n}", "(SourceFile (ClassDecl (Modifiers public open) class (Name A) (TypeParamList < (TypeParam (Name T)) >) (TypeBoundList <: (PathType (PathSegment (NameRef B) (TypeArgList < (PathType (PathSegment (NameRef T))) >))) & (PathType (PathSegment (NameRef C)))) (WhereClause where (GenericConstraint (PathType (PathSegment (NameRef T))) (TypeBoundList <: (PathType (PathSegment (NameRef D))) & (PathType (PathSegment (NameRef E)))))) (DeclBody { (VarDecl (Modifiers public) var (Name x) : (PrimType Int64) = (Literal 1)) (PrimaryInitDecl (Name A) (ParamList ( (Param let (Name y) : (PathType (PathSegment (NameRef T)))) , (Param (Name z) ! : (PrimType Int64) = (Literal 2)) )) (Block { })) (InitDecl init (ParamList ( )) (Block { })) (FinalizerDecl ~ init (ParamList ( )) (Block { })) (PropDecl (Modifiers public mut) prop (Name p) : (PrimType Int64) (PropBody { (PropAccessor get (ParamList ( )) (Block { (RefExpr (NameRef x)) })) (PropAccessor set (ParamList ( (Param (Name v)) )) (Block { (BinExpr (RefExpr (NameRef x)) = (RefExpr (NameRef v))) })) })) (FuncDecl (Modifiers public operator) func (Name [ ]) (ParamList ( (Param (Name i) : (PrimType Int64)) )) (RetType : (PathType (PathSegment (NameRef T)))) (Block { (RefExpr (NameRef y)) })) (FuncDecl (Modifiers operator) func (Name >>) (ParamList ( (Param (Name o) : (PathType (PathSegment (NameRef A) (TypeArgList < (PathType (PathSegment (NameRef T))) >)))) )) (RetType : (PathType (PathSegment (NameRef A) (TypeArgList < (PathType (PathSegment (NameRef T))) >)))) (Block { (ThisExpr this) })) (FuncDecl func (Name abstractOne) (ParamList ( )) (RetType : (PrimType Unit))) })))"),
        ("enum E<T> <: I {\n    | A | B(Int64, T)\n    | C\n    func f() {}\n}", "(SourceFile (EnumDecl enum (Name E) (TypeParamList < (TypeParam (Name T)) >) (TypeBoundList <: (PathType (PathSegment (NameRef I)))) (EnumBody { | (EnumCtor (Name A)) | (EnumCtor (Name B) ( (PrimType Int64) , (PathType (PathSegment (NameRef T))) )) | (EnumCtor (Name C)) (FuncDecl func (Name f) (ParamList ( )) (Block { })) })))"),
        ("interface I { func f(): Unit; prop x: Int64 }", "(SourceFile (InterfaceDecl interface (Name I) (DeclBody { (FuncDecl func (Name f) (ParamList ( )) (RetType : (PrimType Unit))) ; (PropDecl prop (Name x) : (PrimType Int64)) })))"),
        ("extend<T> Array<T> <: I where T <: Hashable {}", "(SourceFile (ExtendDecl extend (TypeParamList < (TypeParam (Name T)) >) (PathType (PathSegment (NameRef Array) (TypeArgList < (PathType (PathSegment (NameRef T))) >))) (TypeBoundList <: (PathType (PathSegment (NameRef I)))) (WhereClause where (GenericConstraint (PathType (PathSegment (NameRef T))) (TypeBoundList <: (PathType (PathSegment (NameRef Hashable)))))) (DeclBody { })))"),
        ("type Alias<T> = (T, Int64) -> ?T", "(SourceFile (TypeAliasDecl type (Name Alias) (TypeParamList < (TypeParam (Name T)) >) = (FuncType ( (PathType (PathSegment (NameRef T))) , (PrimType Int64) ) -> (OptionType ? (PathType (PathSegment (NameRef T)))))))"),
        ("type Named = (a: Int64, b: String)", "(SourceFile (TypeAliasDecl type (Name Named) = (TupleType ( (NamedType (Name a) : (PrimType Int64)) , (NamedType (Name b) : (PathType (PathSegment (NameRef String)))) ))))"),
        ("struct S { let a: Int64; S(b: Int64) { a = b } }", "(SourceFile (StructDecl struct (Name S) (DeclBody { (VarDecl let (Name a) : (PrimType Int64)) ; (PrimaryInitDecl (Name S) (ParamList ( (Param (Name b) : (PrimType Int64)) )) (Block { (BinExpr (RefExpr (NameRef a)) = (RefExpr (NameRef b))) })) })))"),
        ("foreign { func puts(s: CString): Int32; func printf(fmt: CString, ...): Int32 }", "(SourceFile (ForeignBlock (Modifiers foreign) { (FuncDecl func (Name puts) (ParamList ( (Param (Name s) : (PathType (PathSegment (NameRef CString)))) )) (RetType : (PrimType Int32))) ; (FuncDecl func (Name printf) (ParamList ( (Param (Name fmt) : (PathType (PathSegment (NameRef CString)))) , (Param ...) )) (RetType : (PrimType Int32))) }))"),
        ("public macro M(input: Tokens): Tokens { input }", "(SourceFile (MacroDecl (Modifiers public) macro (Name M) (ParamList ( (Param (Name input) : (PathType (PathSegment (NameRef Tokens)))) )) (RetType : (PathType (PathSegment (NameRef Tokens)))) (Block { (RefExpr (NameRef input)) })))"),
        ("@When[os == \"Linux\"]\n@Deprecated[\"use g\", since: \"1.0\"]\nfunc f() {}", "(SourceFile (FuncDecl (Annotation @ (NameRef When) (AnnotationArgList [ (Arg (BinExpr (RefExpr (NameRef os)) == (StringLit \" Linux \"))) ])) (Annotation @ (NameRef Deprecated) (AnnotationArgList [ (Arg (StringLit \" use g \")) , (Arg (NameRef since) : (StringLit \" 1.0 \")) ])) func (Name f) (ParamList ( )) (Block { })))"),
        ("@M[x] @N func g() {}", "(SourceFile (MacroExpandDecl @ (NameRef M) (MacroAttr [ x ]) (MacroExpandDecl @ (NameRef N) (FuncDecl func (Name g) (ParamList ( )) (Block { })))))"),
        ("main(args: Array<String>): Int64 { 0 }", "(SourceFile (MainDecl main (ParamList ( (Param (Name args) : (PathType (PathSegment (NameRef Array) (TypeArgList < (PathType (PathSegment (NameRef String))) >)))) )) (RetType : (PrimType Int64)) (Block { (Literal 0) })))"),
        ("func curried(a: Int64)(b: Int64): Int64 { a + b }", "(SourceFile (FuncDecl func (Name curried) (ParamList ( (Param (Name a) : (PrimType Int64)) )) (ParamList ( (Param (Name b) : (PrimType Int64)) )) (RetType : (PrimType Int64)) (Block { (BinExpr (RefExpr (NameRef a)) + (RefExpr (NameRef b))) })))"),
        ("features { a.b, c }\npackage p", "(SourceFile (FeaturesDirective features { (NameRef a) . (NameRef b) , (NameRef c) }) (PackageHeader package (NameRef p)))"),
        ("func noBody(): Unit", "(SourceFile (FuncDecl func (Name noBody) (ParamList ( )) (RetType : (PrimType Unit)))) !19..19: expected '{': a body is needed here"),
        ("func f(a: Int64 = 1) {}", "(SourceFile (FuncDecl func (Name f) (ParamList ( (Param (Name a) : (PrimType Int64) = (Literal 1)) )) (Block { }))) !15..15: only a named parameter can have a default value"),
        ("func +(a: A) {}", "(SourceFile (FuncDecl func (Name +) (ParamList ( (Param (Name a) : (PathType (PathSegment (NameRef A)))) )) (Block { }))) !5..5: only an operator function is named by an operator"),
        ("struct S { class C {} }", "(SourceFile (StructDecl struct (Name S) (DeclBody { (ClassDecl class (Name C) (DeclBody { })) }))) !11..11: unexpected class declaration in a struct body"),
        ("func f() {}\npackage p", "(SourceFile (FuncDecl func (Name f) (ParamList ( )) (Block { })) (PackageHeader package (NameRef p))) !12..12: the package header must come before imports and declarations"),
        ("var f = @M func g() {}", "(SourceFile (VarDecl var (Name f) = (MacroExpandDecl @ (NameRef M) (FuncDecl func (Name g) (ParamList ( )) (Block { })))))"),
        ("func h() { @M func a() {} is Int64 }", "(SourceFile (FuncDecl func (Name h) (ParamList ( )) (Block { (IsExpr (MacroExpandDecl @ (NameRef M) (FuncDecl func (Name a) (ParamList ( )) (Block { }))) is (PrimType Int64)) }))) !25..25: an operator cannot follow a declaration"),
        ("package a\npackage a", "(SourceFile (PackageHeader package (NameRef a)) (PackageHeader package (NameRef a))) !10..10: a file has one package header only"),
        ("foreign {\npackage a\nimport b.c\n}", "(SourceFile (ForeignBlock (Modifiers foreign) { (PackageHeader package (NameRef a)) (ImportDecl import (ImportTree (NameRef b) . (NameRef c))) })) !10..10: unexpected package header in a foreign block !20..20: unexpected import in a foreign block"),
        ("class A { func f() {} func g() {} }", "(SourceFile (ClassDecl class (Name A) (DeclBody { (FuncDecl func (Name f) (ParamList ( )) (Block { })) (FuncDecl func (Name g) (ParamList ( )) (Block { })) })))"),
        ("func f() {} func g() {}", "(SourceFile (FuncDecl func (Name f) (ParamList ( )) (Block { })) (FuncDecl func (Name g) (ParamList ( )) (Block { }))) !11..11: expected a newline or ';'"),
    ]

    @TestCase
    func eachFileParsesToItsTree() {
        for ((text, expected) in cases) {
            @Expect(sexp(text), expected)
        }
    }
}

@Test
class ParseTest {
    @TestCase
    func triviaGoesBetweenNodesAndADocCommentIntoItsDeclaration() {
        // act
        let root = parse("// file\n\n/** doc */\nfunc f() {} // trailing\n").syntaxNode()

        // assert
        @Expect(root.debugDump(), "SourceFile@0..44\n" +
            "  LineComment@0..7 \"// file\"\n" +
            "  Newline@7..9 \"\\n\\n\"\n" +
            "  FuncDecl@9..31\n" +
            "    BlockComment@9..19 \"/** doc */\"\n" +
            "    Newline@19..20 \"\\n\"\n" +
            "    FuncKw@20..24 \"func\"\n" +
            "    Whitespace@24..25 \" \"\n" +
            "    Name@25..26\n" +
            "      Ident@25..26 \"f\"\n" +
            "    ParamList@26..28\n" +
            "      LParen@26..27 \"(\"\n" +
            "      RParen@27..28 \")\"\n" +
            "    Whitespace@28..29 \" \"\n" +
            "    Block@29..31\n" +
            "      LBrace@29..30 \"{\"\n" +
            "      RBrace@30..31 \"}\"\n" +
            "  Whitespace@31..32 \" \"\n" +
            "  LineComment@32..43 \"// trailing\"\n" +
            "  Newline@43..44 \"\\n\"\n")
    }

    @TestCase[text in [
        "func f( { class } ) ] let",
        "\"\${ \"\${",
        "match (x) { case => case",
        "class A <: { prop }",
        "@@@ ### \\\\ \$\$ ~~~",
        "let x = [1, 2 (3 { 4",
        "import a.{b.{c",
        "if (let <- ) else else",
        "quote(((",
        "}}}}"
    ]]
    func brokenTextStillGivesATreeCoveringIt(text: String) {
        // act
        let parse = parse(text)

        // assert
        @Expect(parse.syntaxNode().text(), text)
        @Expect(parse.errors.size > 0)
    }
}

