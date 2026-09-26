package cjsyntax

import ginkgo.*
import ginkgo.parsing.*

public type CjParse = Parse<SyntaxKind>

public type CjSyntaxNode = SyntaxNode<SyntaxKind>

public type CjSyntaxToken = SyntaxToken<SyntaxKind>

public type CjSyntaxElement = SyntaxElement<SyntaxKind>

type P = Parser<SyntaxKind>

/**
 * Parses a Cangjie source file. Never fails: the tree covers the whole text whatever it holds, what could not be
 * parsed sits in `ErrorNode`s, and everything wrong is in `errors`.
 *
 * The grammar follows the compiler's parser (`cangjie_compiler/src/Parse`), newline rules included: a statement
 * ends at a newline unless an operator (but `-` and `?`) or a `.` carries it on, and `(`, `[`, `{`, `++`, `--`
 * and `?` only continue an expression on the same line.
 */
public func parse(text: String): Parse<SyntaxKind> {
    let lexed = tokenize(text)
    let rules = CangjieTrivia()
    let input = lexed.toInput({k => k.isTrivia()}, {k => k == Newline}, contextual: {k, t => contextualKind(k, t)})
    let p = Parser<SyntaxKind>(input, Eof, ErrorNode)
    sourceFile(p)
    buildTree(lexed, p, rules)
}

/**
 * What is wrong, in words for the one who wrote the code: a missing token by its text, as the compiler says it
 * (`expected '}'`), or by what it is (`expected an identifier`).
 */
public func message(error: ParseError<SyntaxKind>): String {
    match (error) {
        case Expected(kind) => match (kind.fixedText()) {
            case Some(text) => "expected '${text}'"
            case None => "expected ${kind}"
        }
        case Message(message) => message
    }
}

func contextualKind(kind: SyntaxKind, text: String): ?SyntaxKind {
    if (kind != Ident) {
        return None
    }
    match (text) {
        case "JavaMirror" | "JavaImpl" | "JavaHasDefault" | "ObjCMirror" | "ObjCImpl" | "ForeignGetterName" |
            "ForeignSetterName" | "ObjCInit" | "ObjCOptional" | "ForeignName" | "CallingConv" | "C" | "Attribute" |
            "Intrinsic" | "OverflowThrowing" | "OverflowWrapping" | "OverflowSaturating" | "When" | "FastNative" |
            "Annotation" | "ConstSafe" | "Deprecated" | "Frozen" | "EnsurePreparedToMock" | "NonProduct" =>
            BuiltinAnnotationName
        case _ => None
    }
}

/**
 * Comments right before a declaration, with no blank line in between, are its documentation and go inside it.
 */
class CangjieTrivia <: TriviaRules<SyntaxKind> {
    public func isTrivia(kind: SyntaxKind): Bool {
        kind.isTrivia()
    }

    public func attachedTrivia(kind: SyntaxKind, trivia: Array<(SyntaxKind, String)>): Int64 {
        if (!isDocumentable(kind)) {
            return 0
        }
        var attached = 0
        var i = trivia.size - 1
        while (i >= 0) {
            let (k, text) = trivia[i]
            match (k) {
                case LineComment | BlockComment => attached = trivia.size - i
                case Newline where text.count("\n") > 1 => break
                case _ => ()
            }
            i--
        }
        attached
    }
}

func isDocumentable(kind: SyntaxKind): Bool {
    match (kind) {
        case FuncDecl | MainDecl | MacroDecl | ClassDecl | InterfaceDecl | StructDecl | EnumDecl | ExtendDecl |
            TypeAliasDecl | VarDecl | PropDecl | InitDecl | FinalizerDecl | PrimaryInitDecl | EnumCtor |
            MacroExpandDecl | PackageHeader => true
        case _ => false
    }
}

/**
 * How an expression is being parsed, handed down from where it started. The compiler's `ExprKind`.
 */
struct Restrictions {
    Restrictions(
        /** In an `if` or `while` condition: `let pattern <- expr` is an operand. */
        let allowLet: Bool,
        /** The initializer of a `let` condition: operators below `..` end it. */
        let letInit: Bool,
        /** Among comma-separated expressions ending at this token: `a < b, c > d` are comparisons there. */
        let commaCloser: ?SyntaxKind
    ) {}

    static let NONE = Restrictions(false, false, None)
    static let CONDITION = Restrictions(true, false, None)

    static func commaList(closer: SyntaxKind): Restrictions {
        Restrictions(false, false, closer)
    }

    func withoutLet(): Restrictions {
        Restrictions(false, letInit, commaCloser)
    }
}

let MODIFIERS = TokenSet<SyntaxKind>([StaticKw, PublicKw, PrivateKw, InternalKw, ProtectedKw, OverrideKw, RedefKw,
    AbstractKw, SealedKw, OpenKw, ForeignKw, InoutKw, MutKw, UnsafeKw, OperatorKw, ConstKw, CommonKw, SpecificKw])

let PRIM_TYPES = TokenSet<SyntaxKind>([Int8Kw, Int16Kw, Int32Kw, Int64Kw, IntNativeKw, UInt8Kw, UInt16Kw, UInt32Kw,
    UInt64Kw, UIntNativeKw, Float16Kw, Float32Kw, Float64Kw, RuneKw, BoolKw, NothingKw, UnitKw])

let LITERALS = TokenSet<SyntaxKind>([IntLit, FloatLit, RuneLit, ByteLit, RawStringLit, TrueKw, FalseKw])

/**
 * An identifier, or a contextual keyword standing for one.
 */
func atName(p: P, n: Int64): Bool {
    let k = p.nth(n)
    k == Ident || k.isContextualKeyword()
}

/**
 * A contextual keyword followed by an operator is a name in an expression: `open = true`, `public(x)`. The `}`
 * ending an interpolation counts as one, as in `"${open}"`.
 */
func atContextualKeywordAsName(p: P): Bool {
    let next = p.nth(1)
    p.current().isContextualKeyword() && (next.isPunctuation() || next == InterpolationEnd) && next != Tilde &&
        next != At
}

func atModifier(p: P): Bool {
    p.atAny(MODIFIERS) && !atContextualKeywordAsName(p)
}

func atBuiltinAnnotation(p: P): Bool {
    p.at(At) && p.nthContextual(1) == Some(BuiltinAnnotationName)
}

/**
 * `@Name` or `@!Name` for a macro: not a builtin annotation.
 */
func atMacroCall(p: P): Bool {
    (p.at(At) || p.at(AtBang)) && atName(p, 1) && p.nthContextual(1) != Some(BuiltinAnnotationName)
}

/**
 * Consumes a name, remapping a contextual keyword to `Ident`, inside a node of `kind`.
 */
func nameOf(p: P, kind: SyntaxKind): Bool {
    if (!atName(p, 0)) {
        return false
    }
    let m = p.start()
    p.bumpRemap(Ident)
    m.complete(p, kind)
    true
}

func name(p: P): Bool {
    nameOf(p, Name)
}

func nameRef(p: P): Bool {
    nameOf(p, NameRef)
}

func expectName(p: P): Unit {
    if (!name(p)) {
        p.error("expected a name")
    }
}

func expectNameRef(p: P): Unit {
    if (!nameRef(p)) {
        p.error("expected a name")
    }
}

/**
 * Consumes tokens into an error node up to one of `stop`, a newline, or the end.
 */
func skipToLineEnd(p: P, message: String, stop: Array<SyntaxKind>): Unit {
    let m = p.start()
    p.error(message)
    p.bumpAny()
    while (!p.atEof() && !p.newlineBefore() && !p.atAny(stop)) {
        p.bumpAny()
    }
    m.complete(p, ErrorNode)
}
