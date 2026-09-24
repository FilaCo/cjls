package cjsyntax

import std.deriving.*
import ginkgo.Kind

/**
 * Every kind of token and node in a Cangjie syntax tree.
 */
@Derive[Equatable, Hashable]
public enum SyntaxKind {
    // Trivia
    /** spaces, tabs and form feeds */
    | Whitespace
    /** one or more line breaks in a row: what ends a statement */
    | Newline
    | LineComment
    /** `/* */`, which nest */
    | BlockComment
    /** a character the lexer does not know */
    | ErrorToken
    /** what the parser reads past the end; never in a tree */
    | Eof
    /** the contextual kind of an `Ident` naming a builtin annotation; never in a tree */
    | BuiltinAnnotationName
    // Punctuation
    | Dot
    | Comma
    | LParen
    | RParen
    | LBracket
    | RBracket
    | LBrace
    | RBrace
    | StarStar
    | Star
    | Percent
    | Slash
    | Plus
    | Minus
    | PlusPlus
    | MinusMinus
    | AmpAmp
    | PipePipe
    | PipeGt
    | TildeGt
    | Bang
    | Amp
    | Pipe
    | Caret
    | Tilde
    | LtLt
    | Colon
    | ColonColon
    | Semicolon
    | Eq
    | PlusEq
    | MinusEq
    | StarEq
    | StarStarEq
    | SlashEq
    | PercentEq
    | AmpAmpEq
    | PipePipeEq
    | AmpEq
    | PipeEq
    | CaretEq
    | LtLtEq
    | Arrow
    | LArrow
    | FatArrow
    | DotDot
    | DotDotEq
    | DotDotDot
    | Hash
    | At
    | AtBang
    | Question
    | Lt
    | Gt
    | LtEq
    | LtColon
    | EqEq
    | BangEq
    | Dollar
    | Backslash
    // Punctuation the parser glues from `>`, `=` and `?` that are joint: the lexer never makes these
    | GtGt
    | GtEq
    | GtGtEq
    | QuestionQuestion
    // Literals and names
    | IntLit
    | FloatLit
    /** `r'a'` */
    | RuneLit
    /** `b'a'` */
    | ByteLit
    /** `#"..."#`: one token, as it has no interpolation */
    | RawStringLit
    /** the opening quote(s) of a string: `"`, `'`, `"""`, `'''`, `J"` */
    | StringStart
    /** text between the quotes and interpolations, escapes included */
    | StringContent
    /** the closing quote(s) */
    | StringEnd
    | InterpolationStart
    /** the `}` closing an interpolation */
    | InterpolationEnd
    /** an identifier, backquoted or not */
    | Ident
    /** `$name`, in a quote */
    | DollarIdent
    // Keywords, contextual ones included: the parser takes those for names where it can
    | Int8Kw
    | Int16Kw
    | Int32Kw
    | Int64Kw
    | IntNativeKw
    | UInt8Kw
    | UInt16Kw
    | UInt32Kw
    | UInt64Kw
    | UIntNativeKw
    | Float16Kw
    | Float32Kw
    | Float64Kw
    | RuneKw
    | BoolKw
    | NothingKw
    | UnitKw
    | StructKw
    | EnumKw
    | VArrayKw
    | ThisTypeKw
    | PackageKw
    | ImportKw
    | ClassKw
    | InterfaceKw
    | FuncKw
    | MacroKw
    | QuoteKw
    | LetKw
    | VarKw
    | ConstKw
    | TypeKw
    | InitKw
    | ThisKw
    | SuperKw
    | IfKw
    | ElseKw
    | CaseKw
    | TryKw
    | CatchKw
    | FinallyKw
    | ForKw
    | DoKw
    | WhileKw
    | ThrowKw
    | ReturnKw
    | ContinueKw
    | BreakKw
    | InKw
    | MatchKw
    | WhereKw
    | ExtendKw
    | WithKw
    | PropKw
    | StaticKw
    | PublicKw
    | PrivateKw
    | InternalKw
    | ProtectedKw
    | OverrideKw
    | RedefKw
    | AbstractKw
    | SealedKw
    | OpenKw
    | ForeignKw
    | InoutKw
    | MutKw
    | UnsafeKw
    | OperatorKw
    | SpawnKw
    | SynchronizedKw
    | MainKw
    | IsKw
    | AsKw
    | TrueKw
    | FalseKw
    | CommonKw
    | SpecificKw
    | FeaturesKw
    /** `_` */
    | Underscore
    // Nodes
    | SourceFile
    /** what could not be parsed */
    | ErrorNode
    /** a name being declared */
    | Name
    /** a name being used */
    | NameRef
    | FeaturesDirective
    | PackageHeader
    | ImportDecl
    | ImportTree
    | ImportTreeList
    | ImportAlias
    | Annotation
    | AnnotationArgList
    | Modifiers
    | FuncDecl
    | MainDecl
    | MacroDecl
    | ClassDecl
    | InterfaceDecl
    | StructDecl
    | EnumDecl
    | ExtendDecl
    | TypeAliasDecl
    /** `let`, `var` or `const`, of a name or a pattern */
    | VarDecl
    | PropDecl
    | InitDecl
    /** `~init` */
    | FinalizerDecl
    /** a primary constructor, named as its type */
    | PrimaryInitDecl
    | EnumCtor
    | ForeignBlock
    /** a macro call on a declaration */
    | MacroExpandDecl
    /** the `{}` of a class, interface, struct or extend */
    | DeclBody
    | EnumBody
    | PropBody
    /** `get()` or `set(v)` in a property */
    | PropAccessor
    | TypeParamList
    | TypeParam
    | WhereClause
    | GenericConstraint
    /** `<: A & B` */
    | TypeBoundList
    | ParamList
    | Param
    | RetType
    | Block
    | PathType
    | PathSegment
    | PrimType
    | TupleType
    /** `name: T` in a tuple type */
    | NamedType
    | ParenType
    | FuncType
    | OptionType
    | ThisType
    | VArrayType
    | TypeArgList
    | WildcardPat
    | LiteralPat
    /** a lone name: a binding, or an enum constructor without arguments */
    | BindPat
    | TypePat
    | TuplePat
    | EnumPat
    | CatchPat
    | Literal
    | StringLit
    | Interpolation
    | RefExpr
    | MemberAccessExpr
    | CallExpr
    | ArgList
    | Arg
    | TrailingLambdaExpr
    | IndexExpr
    /** `a?` before `.`, `(`, `[` or `{` */
    | OptionalExpr
    | UnaryExpr
    /** assignments included */
    | BinExpr
    | IsExpr
    | AsExpr
    | RangeExpr
    /** `++` and `--` */
    | PostfixExpr
    | ParenExpr
    | TupleExpr
    | ArrayExpr
    | UnitExpr
    | IfExpr
    /** `let pattern <- expr` in a condition */
    | LetExpr
    | MatchExpr
    | MatchBody
    | MatchCase
    /** `where expr` */
    | Guard
    | TryExpr
    | ResourceList
    /** `name: T = expr` in a try-with-resources */
    | ResourceDecl
    | CatchClause
    | FinallyClause
    | ForInExpr
    | WhileExpr
    | DoWhileExpr
    | ThrowExpr
    | ReturnExpr
    | BreakExpr
    | ContinueExpr
    | SpawnExpr
    | SynchronizedExpr
    | UnsafeExpr
    | LambdaExpr
    | LambdaParamList
    | LambdaParam
    | ThisExpr
    | SuperExpr
    | WildcardExpr
    | TypeConvExpr
    /** `Int64` before `.` */
    | PrimTypeExpr
    | VArrayExpr
    | QuoteExpr
    /** `$(expr)` in a quote */
    | QuoteInterpolation
    /** balanced tokens, kept as they are */
    | TokenTree
    | MacroExpandExpr
    /** `[...]` after a macro name */
    | MacroAttr
    /** `(...)` after a macro name */
    | MacroArgs

    public func toString(): String {
        match (this) {
            case Whitespace => "Whitespace"
            case Newline => "Newline"
            case LineComment => "LineComment"
            case BlockComment => "BlockComment"
            case ErrorToken => "ErrorToken"
            case Eof => "Eof"
            case BuiltinAnnotationName => "BuiltinAnnotationName"
            case Dot => "Dot"
            case Comma => "Comma"
            case LParen => "LParen"
            case RParen => "RParen"
            case LBracket => "LBracket"
            case RBracket => "RBracket"
            case LBrace => "LBrace"
            case RBrace => "RBrace"
            case StarStar => "StarStar"
            case Star => "Star"
            case Percent => "Percent"
            case Slash => "Slash"
            case Plus => "Plus"
            case Minus => "Minus"
            case PlusPlus => "PlusPlus"
            case MinusMinus => "MinusMinus"
            case AmpAmp => "AmpAmp"
            case PipePipe => "PipePipe"
            case PipeGt => "PipeGt"
            case TildeGt => "TildeGt"
            case Bang => "Bang"
            case Amp => "Amp"
            case Pipe => "Pipe"
            case Caret => "Caret"
            case Tilde => "Tilde"
            case LtLt => "LtLt"
            case Colon => "Colon"
            case ColonColon => "ColonColon"
            case Semicolon => "Semicolon"
            case Eq => "Eq"
            case PlusEq => "PlusEq"
            case MinusEq => "MinusEq"
            case StarEq => "StarEq"
            case StarStarEq => "StarStarEq"
            case SlashEq => "SlashEq"
            case PercentEq => "PercentEq"
            case AmpAmpEq => "AmpAmpEq"
            case PipePipeEq => "PipePipeEq"
            case AmpEq => "AmpEq"
            case PipeEq => "PipeEq"
            case CaretEq => "CaretEq"
            case LtLtEq => "LtLtEq"
            case Arrow => "Arrow"
            case LArrow => "LArrow"
            case FatArrow => "FatArrow"
            case DotDot => "DotDot"
            case DotDotEq => "DotDotEq"
            case DotDotDot => "DotDotDot"
            case Hash => "Hash"
            case At => "At"
            case AtBang => "AtBang"
            case Question => "Question"
            case Lt => "Lt"
            case Gt => "Gt"
            case LtEq => "LtEq"
            case LtColon => "LtColon"
            case EqEq => "EqEq"
            case BangEq => "BangEq"
            case Dollar => "Dollar"
            case Backslash => "Backslash"
            case GtGt => "GtGt"
            case GtEq => "GtEq"
            case GtGtEq => "GtGtEq"
            case QuestionQuestion => "QuestionQuestion"
            case IntLit => "IntLit"
            case FloatLit => "FloatLit"
            case RuneLit => "RuneLit"
            case ByteLit => "ByteLit"
            case RawStringLit => "RawStringLit"
            case StringStart => "StringStart"
            case StringContent => "StringContent"
            case StringEnd => "StringEnd"
            case InterpolationStart => "InterpolationStart"
            case InterpolationEnd => "InterpolationEnd"
            case Ident => "Ident"
            case DollarIdent => "DollarIdent"
            case Int8Kw => "Int8Kw"
            case Int16Kw => "Int16Kw"
            case Int32Kw => "Int32Kw"
            case Int64Kw => "Int64Kw"
            case IntNativeKw => "IntNativeKw"
            case UInt8Kw => "UInt8Kw"
            case UInt16Kw => "UInt16Kw"
            case UInt32Kw => "UInt32Kw"
            case UInt64Kw => "UInt64Kw"
            case UIntNativeKw => "UIntNativeKw"
            case Float16Kw => "Float16Kw"
            case Float32Kw => "Float32Kw"
            case Float64Kw => "Float64Kw"
            case RuneKw => "RuneKw"
            case BoolKw => "BoolKw"
            case NothingKw => "NothingKw"
            case UnitKw => "UnitKw"
            case StructKw => "StructKw"
            case EnumKw => "EnumKw"
            case VArrayKw => "VArrayKw"
            case ThisTypeKw => "ThisTypeKw"
            case PackageKw => "PackageKw"
            case ImportKw => "ImportKw"
            case ClassKw => "ClassKw"
            case InterfaceKw => "InterfaceKw"
            case FuncKw => "FuncKw"
            case MacroKw => "MacroKw"
            case QuoteKw => "QuoteKw"
            case LetKw => "LetKw"
            case VarKw => "VarKw"
            case ConstKw => "ConstKw"
            case TypeKw => "TypeKw"
            case InitKw => "InitKw"
            case ThisKw => "ThisKw"
            case SuperKw => "SuperKw"
            case IfKw => "IfKw"
            case ElseKw => "ElseKw"
            case CaseKw => "CaseKw"
            case TryKw => "TryKw"
            case CatchKw => "CatchKw"
            case FinallyKw => "FinallyKw"
            case ForKw => "ForKw"
            case DoKw => "DoKw"
            case WhileKw => "WhileKw"
            case ThrowKw => "ThrowKw"
            case ReturnKw => "ReturnKw"
            case ContinueKw => "ContinueKw"
            case BreakKw => "BreakKw"
            case InKw => "InKw"
            case MatchKw => "MatchKw"
            case WhereKw => "WhereKw"
            case ExtendKw => "ExtendKw"
            case WithKw => "WithKw"
            case PropKw => "PropKw"
            case StaticKw => "StaticKw"
            case PublicKw => "PublicKw"
            case PrivateKw => "PrivateKw"
            case InternalKw => "InternalKw"
            case ProtectedKw => "ProtectedKw"
            case OverrideKw => "OverrideKw"
            case RedefKw => "RedefKw"
            case AbstractKw => "AbstractKw"
            case SealedKw => "SealedKw"
            case OpenKw => "OpenKw"
            case ForeignKw => "ForeignKw"
            case InoutKw => "InoutKw"
            case MutKw => "MutKw"
            case UnsafeKw => "UnsafeKw"
            case OperatorKw => "OperatorKw"
            case SpawnKw => "SpawnKw"
            case SynchronizedKw => "SynchronizedKw"
            case MainKw => "MainKw"
            case IsKw => "IsKw"
            case AsKw => "AsKw"
            case TrueKw => "TrueKw"
            case FalseKw => "FalseKw"
            case CommonKw => "CommonKw"
            case SpecificKw => "SpecificKw"
            case FeaturesKw => "FeaturesKw"
            case Underscore => "Underscore"
            case SourceFile => "SourceFile"
            case ErrorNode => "ErrorNode"
            case Name => "Name"
            case NameRef => "NameRef"
            case FeaturesDirective => "FeaturesDirective"
            case PackageHeader => "PackageHeader"
            case ImportDecl => "ImportDecl"
            case ImportTree => "ImportTree"
            case ImportTreeList => "ImportTreeList"
            case ImportAlias => "ImportAlias"
            case Annotation => "Annotation"
            case AnnotationArgList => "AnnotationArgList"
            case Modifiers => "Modifiers"
            case FuncDecl => "FuncDecl"
            case MainDecl => "MainDecl"
            case MacroDecl => "MacroDecl"
            case ClassDecl => "ClassDecl"
            case InterfaceDecl => "InterfaceDecl"
            case StructDecl => "StructDecl"
            case EnumDecl => "EnumDecl"
            case ExtendDecl => "ExtendDecl"
            case TypeAliasDecl => "TypeAliasDecl"
            case VarDecl => "VarDecl"
            case PropDecl => "PropDecl"
            case InitDecl => "InitDecl"
            case FinalizerDecl => "FinalizerDecl"
            case PrimaryInitDecl => "PrimaryInitDecl"
            case EnumCtor => "EnumCtor"
            case ForeignBlock => "ForeignBlock"
            case MacroExpandDecl => "MacroExpandDecl"
            case DeclBody => "DeclBody"
            case EnumBody => "EnumBody"
            case PropBody => "PropBody"
            case PropAccessor => "PropAccessor"
            case TypeParamList => "TypeParamList"
            case TypeParam => "TypeParam"
            case WhereClause => "WhereClause"
            case GenericConstraint => "GenericConstraint"
            case TypeBoundList => "TypeBoundList"
            case ParamList => "ParamList"
            case Param => "Param"
            case RetType => "RetType"
            case Block => "Block"
            case PathType => "PathType"
            case PathSegment => "PathSegment"
            case PrimType => "PrimType"
            case TupleType => "TupleType"
            case NamedType => "NamedType"
            case ParenType => "ParenType"
            case FuncType => "FuncType"
            case OptionType => "OptionType"
            case ThisType => "ThisType"
            case VArrayType => "VArrayType"
            case TypeArgList => "TypeArgList"
            case WildcardPat => "WildcardPat"
            case LiteralPat => "LiteralPat"
            case BindPat => "BindPat"
            case TypePat => "TypePat"
            case TuplePat => "TuplePat"
            case EnumPat => "EnumPat"
            case CatchPat => "CatchPat"
            case Literal => "Literal"
            case StringLit => "StringLit"
            case Interpolation => "Interpolation"
            case RefExpr => "RefExpr"
            case MemberAccessExpr => "MemberAccessExpr"
            case CallExpr => "CallExpr"
            case ArgList => "ArgList"
            case Arg => "Arg"
            case TrailingLambdaExpr => "TrailingLambdaExpr"
            case IndexExpr => "IndexExpr"
            case OptionalExpr => "OptionalExpr"
            case UnaryExpr => "UnaryExpr"
            case BinExpr => "BinExpr"
            case IsExpr => "IsExpr"
            case AsExpr => "AsExpr"
            case RangeExpr => "RangeExpr"
            case PostfixExpr => "PostfixExpr"
            case ParenExpr => "ParenExpr"
            case TupleExpr => "TupleExpr"
            case ArrayExpr => "ArrayExpr"
            case UnitExpr => "UnitExpr"
            case IfExpr => "IfExpr"
            case LetExpr => "LetExpr"
            case MatchExpr => "MatchExpr"
            case MatchBody => "MatchBody"
            case MatchCase => "MatchCase"
            case Guard => "Guard"
            case TryExpr => "TryExpr"
            case ResourceList => "ResourceList"
            case ResourceDecl => "ResourceDecl"
            case CatchClause => "CatchClause"
            case FinallyClause => "FinallyClause"
            case ForInExpr => "ForInExpr"
            case WhileExpr => "WhileExpr"
            case DoWhileExpr => "DoWhileExpr"
            case ThrowExpr => "ThrowExpr"
            case ReturnExpr => "ReturnExpr"
            case BreakExpr => "BreakExpr"
            case ContinueExpr => "ContinueExpr"
            case SpawnExpr => "SpawnExpr"
            case SynchronizedExpr => "SynchronizedExpr"
            case UnsafeExpr => "UnsafeExpr"
            case LambdaExpr => "LambdaExpr"
            case LambdaParamList => "LambdaParamList"
            case LambdaParam => "LambdaParam"
            case ThisExpr => "ThisExpr"
            case SuperExpr => "SuperExpr"
            case WildcardExpr => "WildcardExpr"
            case TypeConvExpr => "TypeConvExpr"
            case PrimTypeExpr => "PrimTypeExpr"
            case VArrayExpr => "VArrayExpr"
            case QuoteExpr => "QuoteExpr"
            case QuoteInterpolation => "QuoteInterpolation"
            case TokenTree => "TokenTree"
            case MacroExpandExpr => "MacroExpandExpr"
            case MacroAttr => "MacroAttr"
            case MacroArgs => "MacroArgs"
        }
    }

    public func isTrivia(): Bool {
        match (this) {
            case Whitespace | Newline | LineComment | BlockComment => true
            case _ => false
        }
    }

    public func isKeyword(): Bool {
        match (this) {
            case Int8Kw | Int16Kw | Int32Kw | Int64Kw | IntNativeKw | UInt8Kw | UInt16Kw | UInt32Kw | UInt64Kw |
                UIntNativeKw | Float16Kw | Float32Kw | Float64Kw | RuneKw | BoolKw | NothingKw | UnitKw | StructKw |
                EnumKw | VArrayKw | ThisTypeKw | PackageKw | ImportKw | ClassKw | InterfaceKw | FuncKw | MacroKw |
                QuoteKw | LetKw | VarKw | ConstKw | TypeKw | InitKw | ThisKw | SuperKw | IfKw | ElseKw | CaseKw |
                TryKw | CatchKw | FinallyKw | ForKw | DoKw | WhileKw | ThrowKw | ReturnKw | ContinueKw | BreakKw |
                InKw | MatchKw | WhereKw | ExtendKw | WithKw | PropKw | StaticKw | PublicKw | PrivateKw |
                InternalKw | ProtectedKw | OverrideKw | RedefKw | AbstractKw | SealedKw | OpenKw | ForeignKw |
                InoutKw | MutKw | UnsafeKw | OperatorKw | SpawnKw | SynchronizedKw | MainKw | IsKw | AsKw | TrueKw |
                FalseKw | CommonKw | SpecificKw | FeaturesKw => true
            case _ => false
        }
    }

    /**
     * The fixed text of a punctuation token or keyword.
     */
    public func fixedText(): ?String {
        match (this) {
            case Dot => "."
            case Comma => ","
            case LParen => "("
            case RParen => ")"
            case LBracket => "["
            case RBracket => "]"
            case LBrace => "{"
            case RBrace => "}"
            case StarStar => "**"
            case Star => "*"
            case Percent => "%"
            case Slash => "/"
            case Plus => "+"
            case Minus => "-"
            case PlusPlus => "++"
            case MinusMinus => "--"
            case AmpAmp => "&&"
            case PipePipe => "||"
            case PipeGt => "|>"
            case TildeGt => "~>"
            case Bang => "!"
            case Amp => "&"
            case Pipe => "|"
            case Caret => "^"
            case Tilde => "~"
            case LtLt => "<<"
            case Colon => ":"
            case ColonColon => "::"
            case Semicolon => ";"
            case Eq => "="
            case PlusEq => "+="
            case MinusEq => "-="
            case StarEq => "*="
            case StarStarEq => "**="
            case SlashEq => "/="
            case PercentEq => "%="
            case AmpAmpEq => "&&="
            case PipePipeEq => "||="
            case AmpEq => "&="
            case PipeEq => "|="
            case CaretEq => "^="
            case LtLtEq => "<<="
            case Arrow => "->"
            case LArrow => "<-"
            case FatArrow => "=>"
            case DotDot => ".."
            case DotDotEq => "..="
            case DotDotDot => "..."
            case Hash => "#"
            case At => "@"
            case AtBang => "@!"
            case Question => "?"
            case Lt => "<"
            case Gt => ">"
            case LtEq => "<="
            case LtColon => "<:"
            case EqEq => "=="
            case BangEq => "!="
            case Dollar => "$"
            case Backslash => "\\"
            case GtGt => ">>"
            case GtEq => ">="
            case GtGtEq => ">>="
            case QuestionQuestion => "??"
            case Int8Kw => "Int8"
            case Int16Kw => "Int16"
            case Int32Kw => "Int32"
            case Int64Kw => "Int64"
            case IntNativeKw => "IntNative"
            case UInt8Kw => "UInt8"
            case UInt16Kw => "UInt16"
            case UInt32Kw => "UInt32"
            case UInt64Kw => "UInt64"
            case UIntNativeKw => "UIntNative"
            case Float16Kw => "Float16"
            case Float32Kw => "Float32"
            case Float64Kw => "Float64"
            case RuneKw => "Rune"
            case BoolKw => "Bool"
            case NothingKw => "Nothing"
            case UnitKw => "Unit"
            case StructKw => "struct"
            case EnumKw => "enum"
            case VArrayKw => "VArray"
            case ThisTypeKw => "This"
            case PackageKw => "package"
            case ImportKw => "import"
            case ClassKw => "class"
            case InterfaceKw => "interface"
            case FuncKw => "func"
            case MacroKw => "macro"
            case QuoteKw => "quote"
            case LetKw => "let"
            case VarKw => "var"
            case ConstKw => "const"
            case TypeKw => "type"
            case InitKw => "init"
            case ThisKw => "this"
            case SuperKw => "super"
            case IfKw => "if"
            case ElseKw => "else"
            case CaseKw => "case"
            case TryKw => "try"
            case CatchKw => "catch"
            case FinallyKw => "finally"
            case ForKw => "for"
            case DoKw => "do"
            case WhileKw => "while"
            case ThrowKw => "throw"
            case ReturnKw => "return"
            case ContinueKw => "continue"
            case BreakKw => "break"
            case InKw => "in"
            case MatchKw => "match"
            case WhereKw => "where"
            case ExtendKw => "extend"
            case WithKw => "with"
            case PropKw => "prop"
            case StaticKw => "static"
            case PublicKw => "public"
            case PrivateKw => "private"
            case InternalKw => "internal"
            case ProtectedKw => "protected"
            case OverrideKw => "override"
            case RedefKw => "redef"
            case AbstractKw => "abstract"
            case SealedKw => "sealed"
            case OpenKw => "open"
            case ForeignKw => "foreign"
            case InoutKw => "inout"
            case MutKw => "mut"
            case UnsafeKw => "unsafe"
            case OperatorKw => "operator"
            case SpawnKw => "spawn"
            case SynchronizedKw => "synchronized"
            case MainKw => "main"
            case IsKw => "is"
            case AsKw => "as"
            case TrueKw => "true"
            case FalseKw => "false"
            case CommonKw => "common"
            case SpecificKw => "specific"
            case FeaturesKw => "features"
            case Underscore => "_"
            case InterpolationStart => "\${"
            case InterpolationEnd => "}"
            case _ => None
        }
    }

    /**
     * The keyword spelled `text`, `Underscore` for `_`.
     */
    public static func keyword(text: String): ?SyntaxKind {
        match (text) {
            case "Int8" => Int8Kw
            case "Int16" => Int16Kw
            case "Int32" => Int32Kw
            case "Int64" => Int64Kw
            case "IntNative" => IntNativeKw
            case "UInt8" => UInt8Kw
            case "UInt16" => UInt16Kw
            case "UInt32" => UInt32Kw
            case "UInt64" => UInt64Kw
            case "UIntNative" => UIntNativeKw
            case "Float16" => Float16Kw
            case "Float32" => Float32Kw
            case "Float64" => Float64Kw
            case "Rune" => RuneKw
            case "Bool" => BoolKw
            case "Nothing" => NothingKw
            case "Unit" => UnitKw
            case "struct" => StructKw
            case "enum" => EnumKw
            case "VArray" => VArrayKw
            case "This" => ThisTypeKw
            case "package" => PackageKw
            case "import" => ImportKw
            case "class" => ClassKw
            case "interface" => InterfaceKw
            case "func" => FuncKw
            case "macro" => MacroKw
            case "quote" => QuoteKw
            case "let" => LetKw
            case "var" => VarKw
            case "const" => ConstKw
            case "type" => TypeKw
            case "init" => InitKw
            case "this" => ThisKw
            case "super" => SuperKw
            case "if" => IfKw
            case "else" => ElseKw
            case "case" => CaseKw
            case "try" => TryKw
            case "catch" => CatchKw
            case "finally" => FinallyKw
            case "for" => ForKw
            case "do" => DoKw
            case "while" => WhileKw
            case "throw" => ThrowKw
            case "return" => ReturnKw
            case "continue" => ContinueKw
            case "break" => BreakKw
            case "in" => InKw
            case "match" => MatchKw
            case "where" => WhereKw
            case "extend" => ExtendKw
            case "with" => WithKw
            case "prop" => PropKw
            case "static" => StaticKw
            case "public" => PublicKw
            case "private" => PrivateKw
            case "internal" => InternalKw
            case "protected" => ProtectedKw
            case "override" => OverrideKw
            case "redef" => RedefKw
            case "abstract" => AbstractKw
            case "sealed" => SealedKw
            case "open" => OpenKw
            case "foreign" => ForeignKw
            case "inout" => InoutKw
            case "mut" => MutKw
            case "unsafe" => UnsafeKw
            case "operator" => OperatorKw
            case "spawn" => SpawnKw
            case "synchronized" => SynchronizedKw
            case "main" => MainKw
            case "is" => IsKw
            case "as" => AsKw
            case "true" => TrueKw
            case "false" => FalseKw
            case "common" => CommonKw
            case "specific" => SpecificKw
            case "features" => FeaturesKw
            case "_" => Underscore
            case _ => None
        }
    }
}

extend SyntaxKind <: Kind<SyntaxKind> {}
