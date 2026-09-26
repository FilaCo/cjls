package loupe

import std.collection.*
import std.deriving.*
import ginkgo.{Direction, SyntaxElement, TokenSet}
// the API's ranges, for whoever asks for a part of a file
public import ginkgo.TextRange
import cjsyntax.{CjSyntaxNode, CjSyntaxToken, SyntaxKind}
import cjsyntax.ast.Decl
import loupe.vfs.FileId
import loupe.db.AnalysisDatabase
import loupe.syntax.parse

/**
 * What a token is, as far as the tree tells: a name at its declaration, or inside a type, taken
 * for one until names resolve. A name at its use is not told yet.
 */
@Derive[Equatable]
public enum HighlightTag <: ToString {
    | Keyword
    | Comment
    | StringLiteral
    | NumberLiteral
    | Operator
    // `@Deprecated` and the other annotations the compiler knows: the `@` and the name
    | BuiltinAnnotation
    // the `@` and the name of a macro call
    | MacroCall
    // `Int64`, `Bool`, `VArray`: keywords naming types
    | BuiltinType
    // a name inside a type
    | TypeName
    | TypeParameter
    | Parameter
    // the name of a declaration, which declares what the outline calls it
    | Declared(StructureKind)

    public func toString(): String {
        match (this) {
            case Keyword => "Keyword"
            case Comment => "Comment"
            case StringLiteral => "StringLiteral"
            case NumberLiteral => "NumberLiteral"
            case Operator => "Operator"
            case BuiltinAnnotation => "BuiltinAnnotation"
            case MacroCall => "MacroCall"
            case BuiltinType => "BuiltinType"
            case TypeName => "TypeName"
            case TypeParameter => "TypeParameter"
            case Parameter => "Parameter"
            case Declared(kind) => kind.toString()
        }
    }
}

@Derive[Equatable]
public enum HighlightModifier <: ToString {
    // the name being declared
    | Declaration
    // a comment documenting the declaration it is attached to
    | Documentation
    // declared with `let` or `const`
    | Readonly
    | Static
    // declared with `@Deprecated`
    | Deprecated
    // a type of the language itself
    | DefaultLibrary

    func bit(): UInt8 {
        match (this) {
            case Declaration => 1
            case Documentation => 2
            case Readonly => 4
            case Static => 8
            case Deprecated => 16
            case DefaultLibrary => 32
        }
    }

    public func toString(): String {
        match (this) {
            case Declaration => "Declaration"
            case Documentation => "Documentation"
            case Readonly => "Readonly"
            case Static => "Static"
            case Deprecated => "Deprecated"
            case DefaultLibrary => "DefaultLibrary"
        }
    }
}

let HIGHLIGHT_MODIFIERS = [HighlightModifier.Declaration, HighlightModifier.Documentation, HighlightModifier.Readonly,
    HighlightModifier.Static, HighlightModifier.Deprecated, HighlightModifier.DefaultLibrary]

/**
 * A set of `HighlightModifier`s.
 */
@Derive[Equatable]
public struct HighlightModifiers <: ToString {
    private HighlightModifiers(let bits: UInt8) {}

    public static let NONE = HighlightModifiers(0)

    public func plus(modifier: HighlightModifier): HighlightModifiers {
        HighlightModifiers(bits | modifier.bit())
    }

    public func contains(modifier: HighlightModifier): Bool {
        (bits & modifier.bit()) != 0
    }

    public func isEmpty(): Bool {
        bits == 0
    }

    public func toString(): String {
        let bits = this.bits
        String.join(HIGHLIGHT_MODIFIERS.filter {m => (bits & m.bit()) != 0}.map {m => m.toString()}, delimiter: ", ")
    }
}

/**
 * A token of a file and what it is. `range` is in UTF-8 bytes (A6).
 */
@Derive[Equatable]
public struct HighlightedRange <: ToString {
    public HighlightedRange(
        public let range: TextRange,
        public let tag: HighlightTag,
        public let modifiers!: HighlightModifiers = HighlightModifiers.NONE
    ) {}

    /**
     * `tag[modifiers]@start..end`.
     */
    public func toString(): String {
        let modifiers = if (this.modifiers.isEmpty()) {
            ""
        } else {
            "[${this.modifiers}]"
        }
        "${tag}${modifiers}@${range.start}..${range.end}"
    }
}

/**
 * The tokens of a file and what each is, in the order of the text, none overlapping: only those
 * `range` intersects if given. A token nothing is known of is left out: punctuation, and a name at
 * its use until names resolve. Whatever sits in an `ErrorNode` is told by its kind alone. Empty for
 * a file the database does not know.
 *
 * Not a query: a range in its key would be a position (A2, A3). What it reads, `parse`, is one.
 */
public func highlight(db: AnalysisDatabase, fileId: FileId, range!: ?TextRange = None): Array<HighlightedRange> {
    let file = db.sourceFile(fileId) ?? return []
    let highlighter = Highlighter(db, range)
    highlighter.walk(parse(db, file).syntaxNode(), false)
    highlighter.result.toArray()
}

/**
 * How many tokens are highlighted between two checks for a write waiting: a large file does not
 * hold one up.
 */
let TOKENS_BETWEEN_CHECKS = 1024

class Highlighter {
    Highlighter(private let db: AnalysisDatabase, private let range: ?TextRange) {}

    let result = ArrayList<HighlightedRange>()
    private var tokens = 0

    func walk(node: CjSyntaxNode, inError: Bool): Unit {
        let inErrorNode = inError || node.kind == SyntaxKind.ErrorNode
        for (child in node.childrenWithTokens()) {
            if (!wanted(child.textRange)) {
                continue
            }
            match (child) {
                case SyntaxElement.Node(inner) => walk(inner, inErrorNode)
                case SyntaxElement.Token(token) => add(token, inErrorNode)
            }
        }
    }

    private func wanted(element: TextRange): Bool {
        let range = this.range
        !element.isEmpty() && match (range) {
            case Some(it) => element.start < it.end && it.start < element.end
            case None => true
        }
    }

    private func add(token: CjSyntaxToken, inError: Bool): Unit {
        tokens++
        if (tokens % TOKENS_BETWEEN_CHECKS == 0) {
            db.unwindIfCancelled()
        }
        match (classify(token, inError)) {
            case Some((tag, modifiers)) => result.add(HighlightedRange(token.textRange, tag, modifiers: modifiers))
            case None => ()
        }
    }
}

let NUMBERS = TokenSet<SyntaxKind>([SyntaxKind.IntLit, SyntaxKind.FloatLit])

let STRINGS = TokenSet<SyntaxKind>([SyntaxKind.RuneLit, SyntaxKind.ByteLit, SyntaxKind.RawStringLit,
    SyntaxKind.StringStart, SyntaxKind.StringContent, SyntaxKind.StringEnd])

let BUILTIN_TYPES = TokenSet<SyntaxKind>([SyntaxKind.Int8Kw, SyntaxKind.Int16Kw, SyntaxKind.Int32Kw,
    SyntaxKind.Int64Kw, SyntaxKind.IntNativeKw, SyntaxKind.UInt8Kw, SyntaxKind.UInt16Kw, SyntaxKind.UInt32Kw,
    SyntaxKind.UInt64Kw, SyntaxKind.UIntNativeKw, SyntaxKind.Float16Kw, SyntaxKind.Float32Kw, SyntaxKind.Float64Kw,
    SyntaxKind.RuneKw, SyntaxKind.BoolKw, SyntaxKind.NothingKw, SyntaxKind.UnitKw, SyntaxKind.VArrayKw])

/**
 * Punctuation that is no operator wherever it is.
 */
let NOT_OPERATORS = TokenSet<SyntaxKind>([SyntaxKind.Dot, SyntaxKind.Comma, SyntaxKind.LParen, SyntaxKind.RParen,
    SyntaxKind.LBracket, SyntaxKind.RBracket, SyntaxKind.LBrace, SyntaxKind.RBrace, SyntaxKind.Colon,
    SyntaxKind.ColonColon, SyntaxKind.Semicolon, SyntaxKind.DotDotDot, SyntaxKind.Hash, SyntaxKind.At,
    SyntaxKind.AtBang, SyntaxKind.Dollar, SyntaxKind.Backslash])

/**
 * Nodes whose punctuation is brackets, separators or a path, not operators: the `<` `>` of type
 * arguments, the `|` between enum constructors, the `*` of an import.
 */
let NO_OPERATORS_IN = TokenSet<SyntaxKind>([SyntaxKind.TypeArgList, SyntaxKind.TypeParamList,
    SyntaxKind.VArrayType, SyntaxKind.EnumBody, SyntaxKind.ImportTree])

let PATTERNS = TokenSet<SyntaxKind>([SyntaxKind.WildcardPat, SyntaxKind.LiteralPat, SyntaxKind.BindPat,
    SyntaxKind.TypePat, SyntaxKind.TuplePat, SyntaxKind.EnumPat])

/**
 * What only holds declarations: those inside are where it is.
 */
let DECLARATION_HOLDERS = TokenSet<SyntaxKind>([SyntaxKind.MacroExpandDecl, SyntaxKind.ForeignBlock])

type Highlight = (HighlightTag, HighlightModifiers)

func tagged(tag: HighlightTag): ?Highlight {
    (tag, HighlightModifiers.NONE)
}

func declaration(tag: HighlightTag): ?Highlight {
    (tag, HighlightModifiers.NONE.plus(HighlightModifier.Declaration))
}

/**
 * By where the token is, then by its kind; in an `ErrorNode` by its kind alone.
 */
func classify(token: CjSyntaxToken, inError: Bool): ?Highlight {
    let kind = token.kind
    let parent = token.parent
    if (kind == SyntaxKind.LineComment || kind == SyntaxKind.BlockComment) {
        if (isDocumentation(token)) {
            (HighlightTag.Comment, HighlightModifiers.NONE.plus(HighlightModifier.Documentation))
        } else {
            tagged(HighlightTag.Comment)
        }
    } else if (NUMBERS.contains(kind)) {
        tagged(HighlightTag.NumberLiteral)
    } else if (STRINGS.contains(kind)) {
        tagged(HighlightTag.StringLiteral)
    } else if (BUILTIN_TYPES.contains(kind)) {
        (HighlightTag.BuiltinType, HighlightModifiers.NONE.plus(HighlightModifier.DefaultLibrary))
    } else if (!inError && parent.kind == SyntaxKind.Name) {
        declaredName(parent)
    } else if (!inError && parent.kind == SyntaxKind.NameRef) {
        usedName(parent)
    } else if (!inError && (kind == SyntaxKind.At || kind == SyntaxKind.AtBang)) {
        callOrAnnotation(parent)
    } else if (!inError && (kind == SyntaxKind.Ident && parent.kind == SyntaxKind.PropAccessor ||
        kind == SyntaxKind.Tilde && parent.kind == SyntaxKind.FinalizerDecl)) {
        // `get` and `set`, and the `~` of `~init`
        tagged(HighlightTag.Keyword)
    } else if (kind.isKeyword()) {
        tagged(HighlightTag.Keyword)
    } else if (kind.isPunctuation() && !NOT_OPERATORS.contains(kind) && (inError ||
        !NO_OPERATORS_IN.contains(parent.kind))) {
        tagged(HighlightTag.Operator)
    } else {
        None
    }
}

/**
 * A comment is documentation when the parser gave it to a declaration, before all of it.
 */
func isDocumentation(comment: CjSyntaxToken): Bool {
    let owner = comment.parent.kind
    (Decl.canCast(owner) || owner == SyntaxKind.PackageHeader) &&
        (comment.siblingsWithTokens(Direction.Prev) |> all {element: SyntaxElement<SyntaxKind> => element.kind.isTrivia()})
}

/**
 * The name `name` declares, by what declares it.
 */
func declaredName(name: CjSyntaxNode): ?Highlight {
    let owner = name.parent ?? return None
    match (owner.kind) {
        case SyntaxKind.TypeParam => declaration(HighlightTag.TypeParameter)
        case SyntaxKind.LambdaParam | SyntaxKind.NamedType => declaration(HighlightTag.Parameter)
        case SyntaxKind.Param => parameter(owner)
        case SyntaxKind.BindPat | SyntaxKind.TypePat => binding(owner)
        case SyntaxKind.CatchPat | SyntaxKind.ResourceDecl => declaration(HighlightTag.Declared(StructureKind.Variable))
        case _ => declared(Decl.cast(owner) ?? return None)
    }
}

/**
 * A parameter of a primary constructor declared `let` or `var` is a member variable as well.
 */
func parameter(param: CjSyntaxNode): ?Highlight {
    let modifiers = HighlightModifiers.NONE.plus(HighlightModifier.Declaration)
    if (hasToken(param, SyntaxKind.LetKw)) {
        (HighlightTag.Declared(StructureKind.Field), modifiers.plus(HighlightModifier.Readonly))
    } else if (hasToken(param, SyntaxKind.VarKw)) {
        (HighlightTag.Declared(StructureKind.Field), modifiers)
    } else {
        (HighlightTag.Parameter, modifiers)
    }
}

/**
 * A name a pattern binds. In a `case` or a `let` condition a lone name may as well be an enum
 * constructor, which only names resolved tell.
 */
func binding(pattern: CjSyntaxNode): ?Highlight {
    let site = (pattern.ancestors() |> filter {node: CjSyntaxNode => !PATTERNS.contains(node.kind)} |>
        first<CjSyntaxNode>) ?? return None
    match (Decl.cast(site)) {
        case Some(decl) => declared(decl)
        case None where site.kind == SyntaxKind.ForInExpr || pattern.kind == SyntaxKind.TypePat =>
            declaration(HighlightTag.Declared(StructureKind.Variable))
        case None => None
    }
}

/**
 * The name of `decl`, as the outline has it, with what its modifiers and annotations tell.
 */
func declared(decl: Decl): ?Highlight {
    let node = decl.syntax
    let kind = declarationKind(decl, isMember(node)) ?? return None
    var modifiers = HighlightModifiers.NONE.plus(HighlightModifier.Declaration)
    if (hasModifier(node, SyntaxKind.StaticKw)) {
        modifiers = modifiers.plus(HighlightModifier.Static)
    }
    if (kind == StructureKind.Constant || hasToken(node, SyntaxKind.LetKw)) {
        modifiers = modifiers.plus(HighlightModifier.Readonly)
    }
    if (isDeprecated(node)) {
        modifiers = modifiers.plus(HighlightModifier.Deprecated)
    }
    (HighlightTag.Declared(kind), modifiers)
}

/**
 * Whether `decl` is a type's member, as the outline has it: inside its body, maybe through a macro
 * call or a `foreign` block.
 */
func isMember(decl: CjSyntaxNode): Bool {
    let container = decl.ancestors() |>
        filter {node: CjSyntaxNode => node != decl && !DECLARATION_HOLDERS.contains(node.kind)} |> first<CjSyntaxNode>
    match (container) {
        case Some(it) => it.kind == SyntaxKind.DeclBody || it.kind == SyntaxKind.EnumBody
        case None => false
    }
}

func hasToken(node: CjSyntaxNode, kind: SyntaxKind): Bool {
    node.childrenWithTokens() |> any {element: SyntaxElement<SyntaxKind> => element.kind == kind}
}

func hasModifier(decl: CjSyntaxNode, kind: SyntaxKind): Bool {
    decl.children() |> any {node: CjSyntaxNode => node.kind == SyntaxKind.Modifiers && hasToken(node, kind)}
}

func isDeprecated(decl: CjSyntaxNode): Bool {
    decl.children() |> any {
        annotation: CjSyntaxNode => annotation.kind == SyntaxKind.Annotation && (annotation.children() |> any {
            name: CjSyntaxNode => name.kind == SyntaxKind.NameRef && name.text() == "Deprecated"
        })
    }
}

/**
 * A name used: known only in an annotation, a macro call, or a type, which it is taken to name.
 */
func usedName(nameRef: CjSyntaxNode): ?Highlight {
    let owner = nameRef.parent ?? return None
    match (owner.kind) {
        case SyntaxKind.PathSegment where (owner.parent?.kind == Some(SyntaxKind.PathType)) => tagged(
            HighlightTag.TypeName)
        case _ => callOrAnnotation(owner)
    }
}

func callOrAnnotation(node: CjSyntaxNode): ?Highlight {
    match (node.kind) {
        case SyntaxKind.Annotation => tagged(HighlightTag.BuiltinAnnotation)
        case SyntaxKind.MacroExpandDecl | SyntaxKind.MacroExpandExpr => tagged(HighlightTag.MacroCall)
        case _ => None
    }
}
