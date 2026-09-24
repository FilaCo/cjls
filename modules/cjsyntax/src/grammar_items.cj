package cjsyntax

import std.deriving.*
import ginkgo.TokenSet
import ginkgo.parsing.*

/**
 * Where declarations are being parsed, which decides what an identifier starting one means and which
 * declarations are allowed.
 */
@Derive[Equatable]
enum Scope {
    | InTopLevel
    /** `Name(` is a primary constructor in a class or struct body. */
    | InClassBody
    | InStructBody
    | InInterfaceBody
    | InExtendBody
    /** `Name` is an enum constructor. */
    | InEnumBody
    | InBlock
    /** A parameter list: a macro call applies to a parameter. */
    | InParams
    /** What a macro call in an expression applies to: anything goes. */
    | InMacroInput
    | InForeignBlock

    func describe(): String {
        match (this) {
            case InTopLevel => "the top level"
            case InClassBody => "a class body"
            case InStructBody => "a struct body"
            case InInterfaceBody => "an interface body"
            case InExtendBody => "an extend body"
            case InEnumBody => "an enum body"
            case InBlock => "a block"
            case InParams => "a parameter list"
            case InMacroInput => "a macro input"
            case InForeignBlock => "a foreign block"
        }
    }

    /**
     * Whether a declaration of `kind` may appear here, as the compiler's parser checks it.
     */
    func allows(kind: SyntaxKind): Bool {
        match (this) {
            case InTopLevel => match (kind) {
                case PropDecl | InitDecl | FinalizerDecl | PrimaryInitDecl | EnumCtor => false
                case _ => true
            }
            case InForeignBlock => match (kind) {
                case PropDecl | InitDecl | FinalizerDecl | PrimaryInitDecl | EnumCtor | PackageHeader | ImportDecl |
                    FeaturesDirective => false
                case _ => true
            }
            case InClassBody => match (kind) {
                case FuncDecl | VarDecl | PropDecl | InitDecl | FinalizerDecl | PrimaryInitDecl | MacroExpandDecl => true
                case _ => false
            }
            case InStructBody => match (kind) {
                case FuncDecl | VarDecl | PropDecl | InitDecl | PrimaryInitDecl | MacroExpandDecl => true
                case _ => false
            }
            case InInterfaceBody | InExtendBody => match (kind) {
                case FuncDecl | PropDecl | MacroExpandDecl => true
                case _ => false
            }
            case InEnumBody => match (kind) {
                case FuncDecl | PropDecl | EnumCtor | MacroExpandDecl => true
                case _ => false
            }
            case InBlock => match (kind) {
                case FuncDecl | VarDecl | MacroExpandDecl => true
                case _ => false
            }
            case InParams | InMacroInput => true
        }
    }
}

func describeDecl(kind: SyntaxKind): String {
    match (kind) {
        case FuncDecl => "function declaration"
        case MainDecl => "main function"
        case MacroDecl => "macro declaration"
        case ClassDecl => "class declaration"
        case StructDecl => "struct declaration"
        case InterfaceDecl => "interface declaration"
        case EnumDecl => "enum declaration"
        case ExtendDecl => "extend declaration"
        case TypeAliasDecl => "type alias declaration"
        case VarDecl => "variable declaration"
        case PropDecl => "property declaration"
        case InitDecl => "constructor"
        case FinalizerDecl => "finalizer"
        case PrimaryInitDecl => "primary constructor"
        case EnumCtor => "enum constructor"
        case PackageHeader => "package header"
        case ImportDecl => "import"
        case FeaturesDirective => "features directive"
        case ForeignBlock => "foreign block"
        case _ => "declaration"
    }
}

struct ModifierInfo {
    ModifierInfo(
        let isForeign: Bool,
        let lastConst: Bool,
        let isOperator: Bool,
        /** `common` or `specific`: a multiplatform declaration, which may leave out its body. */
        let isPlatform: Bool
    ) {}
}

/**
 * What a declaration's rules depend on beyond its own tokens.
 */
struct DeclContext {
    DeclContext(let scope: Scope, let mods: ModifierInfo, let annotated: Bool) {}

    /**
     * Whether a function or property here may leave out its body: in a class or an interface it is abstract, in
     * a foreign block or with `foreign` it is foreign; `common` and annotations like `@Intrinsic` allow it too.
     */
    func bodyOptional(): Bool {
        mods.isForeign || mods.isPlatform || annotated || scope == InClassBody || scope == InInterfaceBody ||
            scope == InForeignBlock || scope == InMacroInput
    }
}

/**
 * Where a file's preamble is at: `features`, then `package`, then imports, then declarations.
 */
class Preamble {
    var stage = 0
}

/**
 * features? package? import* declaration*, separated by newlines or `;`.
 */
func sourceFile(p: P): Unit {
    let m = p.start()
    let preamble = Preamble()
    var needSeparator = false
    while (!p.atEof()) {
        if (p.eat(Semicolon)) {
            needSeparator = false
            continue
        }
        if (needSeparator && !p.newlineBefore()) {
            p.error("expected a newline or ';'")
        }
        declaration(p, InTopLevel, preamble: preamble)
        needSeparator = true
    }
    m.complete(p, SourceFile)
}

/**
 * Annotations, modifiers, then whatever declaration follows; an error node if none does.
 */
func declaration(p: P, scope: Scope, preamble!: ?Preamble = None): Unit {
    let m = p.start()
    let before = p.position
    annotations(p)
    let annotated = p.position != before
    let mods = modifiers(p)
    if (let Some(kind) <- declKind(p, scope, mods)) {
        if (!scope.allows(kind)) {
            p.error("unexpected ${describeDecl(kind)} in ${scope.describe()}")
        }
        if (let Some(order) <- preamble) {
            checkPreamble(p, order, kind)
        }
        parseDecl(p, m, DeclContext(scope, mods, annotated), kind)
        return
    }
    if (p.position != before) {
        if (p.atEof()) {
            // Annotations dangling at the end of a file: the compiler lets them be.
            m.abandon(p)
            return
        }
        p.error("expected a declaration")
        m.complete(p, ErrorNode)
        return
    }
    m.abandon(p)
    skipToLineEnd(p, "expected a declaration", [RBrace])
}

func checkPreamble(p: P, preamble: Preamble, kind: SyntaxKind): Unit {
    let (stage, message) = match (kind) {
        case FeaturesDirective => (0, "the features directive must come first in a file")
        case PackageHeader => (1, "the package header must come before imports and declarations")
        case ImportDecl => (2, "imports must come before declarations")
        case _ => (3, "")
    }
    if (preamble.stage > stage) {
        p.error(message)
    } else if (kind == PackageHeader && preamble.stage == stage) {
        p.error("a file has one package header only")
    } else {
        preamble.stage = stage
    }
}

func atDeclStart(p: P): Bool {
    if (atBuiltinAnnotation(p)) {
        return !p.nthAt(2, LBrace)
    }
    if (atModifier(p)) {
        return !(p.at(UnsafeKw) && p.nthAt(1, LBrace))
    }
    match (p.current()) {
        case FuncKw | MacroKw | LetKw | VarKw | EnumKw | TypeKw | StructKw | ClassKw | InterfaceKw | MainKw |
            ExtendKw => true
        case _ => false
    }
}

/**
 * The declaration starting at the current token, annotations and modifiers aside; `None` if none does.
 */
func declKind(p: P, scope: Scope, mods: ModifierInfo): ?SyntaxKind {
    match (p.current()) {
        case FuncKw => FuncDecl
        case MainKw => MainDecl
        case MacroKw where p.nthAt(1, PackageKw) => PackageHeader
        case MacroKw => MacroDecl
        case ClassKw => ClassDecl
        case StructKw => StructDecl
        case InterfaceKw => InterfaceDecl
        case EnumKw => EnumDecl
        case ExtendKw => ExtendDecl
        case TypeKw => TypeAliasDecl
        case LetKw | VarKw => VarDecl
        case PropKw => PropDecl
        case InitKw => InitDecl
        case Tilde where p.nthAt(1, InitKw) => FinalizerDecl
        case PackageKw => PackageHeader
        case ImportKw => ImportDecl
        case FeaturesKw where p.nthAt(1, LBrace) => FeaturesDirective
        case LBrace where mods.isForeign => ForeignBlock
        case At | AtBang where atMacroCall(p) => MacroExpandDecl
        case _ where (scope == InClassBody || scope == InStructBody) && atName(p, 0) &&
            (p.nthAt(1, LParen) || p.nthAt(1, Lt)) => PrimaryInitDecl
        case _ where scope == InEnumBody && atName(p, 0) => EnumCtor
        case _ where mods.lastConst && (atName(p, 0) || p.at(Underscore) || p.at(LParen)) => VarDecl
        case _ => None
    }
}

/**
 * Completes `m`, holding annotations and modifiers, with the declaration of `kind` at the current token.
 */
func parseDecl(p: P, m: Marker, ctx: DeclContext, kind: SyntaxKind): Unit {
    let scope = ctx.scope
    match (kind) {
        case FuncDecl => funcDecl(p, m, ctx)
        case MainDecl => mainDecl(p, m, ctx)
        case MacroDecl => macroDecl(p, m, ctx)
        case ClassDecl => typeDecl(p, m, ClassKw, ClassDecl, InClassBody)
        case StructDecl => typeDecl(p, m, StructKw, StructDecl, InStructBody)
        case InterfaceDecl => typeDecl(p, m, InterfaceKw, InterfaceDecl, InInterfaceBody)
        case EnumDecl => enumDecl(p, m)
        case ExtendDecl => extendDecl(p, m)
        case TypeAliasDecl => typeAliasDecl(p, m)
        case VarDecl =>
            if (p.at(LetKw) || p.at(VarKw)) {
                p.bumpAny()
            }
            varDecl(p, m)
        case PropDecl => propDecl(p, m, ctx)
        case InitDecl => initDecl(p, m, ctx)
        case FinalizerDecl => finalizerDecl(p, m, ctx)
        case PackageHeader => packageHeader(p, m)
        case ImportDecl => importDecl(p, m)
        case FeaturesDirective => featuresDirective(p, m)
        case ForeignBlock => foreignBlock(p, m)
        case MacroExpandDecl => macroExpandDecl(p, m, scope)
        case PrimaryInitDecl => primaryInitDecl(p, m, ctx)
        case _ => enumCtor(p, m)
    }
}

func annotations(p: P): Unit {
    while (atBuiltinAnnotation(p)) {
        let m = p.start()
        p.bump(At)
        nameRef(p)
        if (p.at(LBracket)) {
            argList(p, LBracket, RBracket, AnnotationArgList)
        }
        m.complete(p, Annotation)
    }
}

func modifiers(p: P): ModifierInfo {
    if (!atModifier(p)) {
        return ModifierInfo(false, false, false, false)
    }
    let m = p.start()
    var isForeign = false
    var lastConst = false
    var isOperator = false
    var isPlatform = false
    while (atModifier(p)) {
        isForeign = isForeign || p.at(ForeignKw)
        isOperator = isOperator || p.at(OperatorKw)
        isPlatform = isPlatform || p.at(CommonKw) || p.at(SpecificKw)
        lastConst = p.at(ConstKw)
        p.bumpAny()
    }
    m.complete(p, Modifiers)
    ModifierInfo(isForeign, lastConst, isOperator, isPlatform)
}

func funcDecl(p: P, m: Marker, ctx: DeclContext): Unit {
    p.bump(FuncKw)
    funcName(p, ctx.mods.isOperator)
    functionRest(p, ctx.bodyOptional())
    m.complete(p, FuncDecl)
}

let OVERLOADABLE_OPERATORS = TokenSet<SyntaxKind>([Bang, Plus, Minus, StarStar, Star, Slash, Percent, LtLt, Lt, LtEq,
    Gt, EqEq, BangEq, Amp, Caret, Pipe, Tilde])

/**
 * A name, `main`, or for an `operator func`, the operator: `[]`, `()`, `>>`, `>=` and the plain ones.
 */
func funcName(p: P, isOperator: Bool): Unit {
    if (atName(p, 0) || p.at(MainKw)) {
        let m = p.start()
        p.bumpRemap(Ident)
        m.complete(p, Name)
        return
    }
    let m = p.start()
    let operatorAhead = (p.at(LBracket) && p.nthAt(1, RBracket)) || p.at(LParen) && p.nthAt(1, RParen) ||
        p.atAny(OVERLOADABLE_OPERATORS)
    if (!isOperator && operatorAhead) {
        p.error("only an operator function is named by an operator")
    }
    if (p.at(LBracket) && p.nthAt(1, RBracket)) {
        p.bump(LBracket)
        p.bump(RBracket)
    } else if (p.at(LParen) && p.nthAt(1, RParen) && (p.nthAt(2, LParen) || p.nthAt(2, Lt))) {
        p.bump(LParen)
        p.bump(RParen)
    } else if (p.atComposite([Gt, Gt])) {
        p.bumpComposite(GtGt, 2)
    } else if (p.atComposite([Gt, Eq])) {
        p.bumpComposite(GtEq, 2)
    } else if (p.atAny(OVERLOADABLE_OPERATORS)) {
        p.bumpAny()
    } else {
        m.abandon(p)
        p.error("expected a name")
        return
    }
    m.complete(p, Name)
}

func paramLists(p: P): Unit {
    if (!p.at(LParen)) {
        p.error("expected '('")
        return
    }
    while (p.at(LParen)) {
        paramList(p, true)
    }
}

/**
 * `(params)`; a setter's `(v)` alone takes no type.
 */
func paramList(p: P, typed: Bool): Unit {
    let m = p.start()
    p.bump(LParen)
    while (!p.at(RParen) && !p.atEof() && !p.at(LBrace)) {
        param(p, typed)
        if (!p.eat(Comma)) {
            break
        }
    }
    p.expect(RParen)
    m.complete(p, ParamList)
}

/**
 * `a: T`, `a!: T = v`, `let a: T` in a primary constructor, `...` in a foreign function, `v` in a setter.
 */
func param(p: P, typed: Bool): Unit {
    let m = p.start()
    if (atMacroCall(p)) {
        macroExpandDecl(p, m, InParams)
        return
    }
    annotations(p)
    modifiers(p)
    if (p.at(LetKw) || p.at(VarKw)) {
        p.bumpAny()
    }
    if (p.eat(DotDotDot)) {
        m.complete(p, Param)
        return
    }
    if (!p.eat(Underscore)) {
        if (!name(p)) {
            p.errRecover("expected a parameter", [Comma, RParen, LBrace, RBrace])
            m.complete(p, Param)
            return
        }
    }
    let named = p.eat(Bang)
    if (p.eat(Colon)) {
        typ(p)
    } else if (typed) {
        p.error("expected ':'")
    }
    if (p.at(Eq)) {
        if (!named) {
            p.error("only a named parameter can have a default value")
        }
        p.bump(Eq)
        exprOrError(p, Restrictions.NONE)
    }
    m.complete(p, Param)
}

func retType(p: P): Unit {
    let m = p.start()
    p.bump(Colon)
    typ(p)
    m.complete(p, RetType)
}

func typeParamList(p: P): Unit {
    let m = p.start()
    p.bump(Lt)
    while (!p.at(Gt) && !p.atEof()) {
        if (atName(p, 0)) {
            let tp = p.start()
            name(p)
            tp.complete(p, TypeParam)
        } else {
            p.errRecover("expected a type parameter", [Gt, Comma, LParen, LBrace, LtColon])
            if (!p.at(Comma)) {
                break
            }
        }
        if (!p.eat(Comma)) {
            break
        }
    }
    p.expect(Gt)
    m.complete(p, TypeParamList)
}

func typeBoundList(p: P): Unit {
    let m = p.start()
    p.bump(LtColon)
    typ(p)
    while (p.eat(Amp)) {
        typ(p)
    }
    m.complete(p, TypeBoundList)
}

func whereClause(p: P): Unit {
    let m = p.start()
    p.bump(WhereKw)
    while (true) {
        let c = p.start()
        typ(p)
        if (p.at(LtColon)) {
            typeBoundList(p)
        } else {
            p.error("expected '<:'")
        }
        c.complete(p, GenericConstraint)
        if (!p.eat(Comma)) {
            break
        }
    }
    m.complete(p, WhereClause)
}

/**
 * `class`, `struct` and `interface`: a name, type parameters, supertypes, constraints, a body.
 */
func typeDecl(p: P, m: Marker, keyword: SyntaxKind, kind: SyntaxKind, bodyScope: Scope): Unit {
    p.bump(keyword)
    expectName(p)
    if (p.at(Lt)) {
        typeParamList(p)
    }
    if (p.at(LtColon)) {
        typeBoundList(p)
    }
    if (p.at(WhereKw)) {
        whereClause(p)
    }
    if (p.at(LBrace)) {
        declBody(p, bodyScope)
    } else {
        p.error("expected '{'")
    }
    m.complete(p, kind)
}

func declBody(p: P, scope: Scope): Unit {
    let m = p.start()
    p.bump(LBrace)
    members(p, scope)
    p.expect(RBrace)
    m.complete(p, DeclBody)
}

func members(p: P, scope: Scope): Unit {
    while (true) {
        while (p.eat(Semicolon)) {}
        if (p.at(RBrace) || p.atEof()) {
            return
        }
        declaration(p, scope)
    }
}

func enumDecl(p: P, m: Marker): Unit {
    p.bump(EnumKw)
    expectName(p)
    if (p.at(Lt)) {
        typeParamList(p)
    }
    if (p.at(LtColon)) {
        typeBoundList(p)
    }
    if (p.at(WhereKw)) {
        whereClause(p)
    }
    if (p.at(LBrace)) {
        enumBody(p)
    } else {
        p.error("expected '{'")
    }
    m.complete(p, EnumDecl)
}

/**
 * `{ | A | B(T) | ... members }`: constructors separated by `|`, then members.
 */
func enumBody(p: P): Unit {
    let m = p.start()
    p.bump(LBrace)
    p.eat(Pipe)
    while (!p.at(RBrace) && !p.atEof()) {
        if (!p.eat(DotDotDot)) {
            if (atName(p, 0) || atMacroCall(p) || atBuiltinAnnotation(p)) {
                declaration(p, InEnumBody)
            } else {
                p.error("expected an enum constructor")
                break
            }
        }
        while (p.eat(Semicolon)) {}
        if (!p.eat(Pipe)) {
            break
        }
    }
    members(p, InEnumBody)
    p.expect(RBrace)
    m.complete(p, EnumBody)
}

func enumCtor(p: P, m: Marker): Unit {
    name(p)
    if (p.eat(LParen)) {
        while (!p.at(RParen) && !p.atEof()) {
            typ(p)
            if (!p.eat(Comma)) {
                break
            }
            if (p.at(RParen)) {
                p.error("expected a type")
            }
        }
        p.expect(RParen)
    }
    m.complete(p, EnumCtor)
}

func extendDecl(p: P, m: Marker): Unit {
    p.bump(ExtendKw)
    if (p.at(Lt)) {
        typeParamList(p)
    }
    typ(p)
    if (p.at(LtColon)) {
        typeBoundList(p)
    }
    if (p.at(WhereKw)) {
        whereClause(p)
    }
    if (p.at(LBrace)) {
        declBody(p, InExtendBody)
    } else {
        p.error("expected '{'")
    }
    m.complete(p, ExtendDecl)
}

func typeAliasDecl(p: P, m: Marker): Unit {
    p.bump(TypeKw)
    expectName(p)
    if (p.at(Lt)) {
        typeParamList(p)
    }
    if (p.expect(Eq)) {
        typ(p)
    }
    m.complete(p, TypeAliasDecl)
}

/**
 * After `let`, `var`, or a `const` modifier: a name or an irrefutable pattern, a type, an initializer.
 */
func varDecl(p: P, m: Marker): Unit {
    if (p.at(Underscore) || p.at(LParen) || (atName(p, 0) && (p.nthAt(1, LParen) || p.nthAt(1, Dot) || p.nthAt(1, Lt)))) {
        pattern(p)
    } else if (!name(p)) {
        p.error("expected a name or a pattern")
    }
    if (p.eat(Colon)) {
        typ(p)
    }
    if (p.eat(Eq)) {
        exprOrError(p, Restrictions.NONE)
    }
    m.complete(p, VarDecl)
}

func propDecl(p: P, m: Marker, ctx: DeclContext): Unit {
    p.bump(PropKw)
    expectName(p)
    if (p.eat(Colon)) {
        typ(p)
    } else {
        p.error("expected ':'")
    }
    if (p.at(LBrace)) {
        propBody(p)
    } else if (!ctx.bodyOptional()) {
        p.error("expected '{': a property needs a body here")
    }
    m.complete(p, PropDecl)
}

func propBody(p: P): Unit {
    let m = p.start()
    p.bump(LBrace)
    while (true) {
        while (p.eat(Semicolon)) {}
        if (p.at(RBrace) || p.atEof()) {
            break
        }
        let a = p.start()
        annotations(p)
        modifiers(p)
        if (p.at(Ident)) {
            p.bump(Ident)
            while (p.at(LParen)) {
                paramList(p, false)
            }
            if (p.at(LBrace)) {
                block(p)
            } else {
                p.error("expected '{'")
            }
            a.complete(p, PropAccessor)
        } else {
            a.abandon(p)
            skipToLineEnd(p, "expected 'get' or 'set'", [RBrace])
        }
    }
    p.expect(RBrace)
    m.complete(p, PropBody)
}

func initDecl(p: P, m: Marker, ctx: DeclContext): Unit {
    p.bump(InitKw)
    // A constructor of a mirror type has no body, which only the type's annotations tell.
    functionRest(p, true)
    m.complete(p, InitDecl)
}

func finalizerDecl(p: P, m: Marker, ctx: DeclContext): Unit {
    p.bump(Tilde)
    p.bump(InitKw)
    functionRest(p, true)
    m.complete(p, FinalizerDecl)
}

func primaryInitDecl(p: P, m: Marker, ctx: DeclContext): Unit {
    name(p)
    functionRest(p, true)
    m.complete(p, PrimaryInitDecl)
}

func mainDecl(p: P, m: Marker, ctx: DeclContext): Unit {
    p.bump(MainKw)
    functionRest(p, ctx.annotated)
    m.complete(p, MainDecl)
}

func macroDecl(p: P, m: Marker, ctx: DeclContext): Unit {
    p.bump(MacroKw)
    expectName(p)
    functionRest(p, ctx.annotated)
    m.complete(p, MacroDecl)
}

/**
 * What follows the name of a function-like declaration.
 */
func functionRest(p: P, bodyOptional: Bool): Unit {
    if (p.at(Lt)) {
        typeParamList(p)
    }
    paramLists(p)
    if (p.at(Colon)) {
        retType(p)
    }
    if (p.at(WhereKw)) {
        whereClause(p)
    }
    if (p.at(LBrace)) {
        block(p)
    } else if (!bodyOptional) {
        p.error("expected '{': a body is needed here")
    }
}

func foreignBlock(p: P, m: Marker): Unit {
    p.bump(LBrace)
    members(p, InForeignBlock)
    p.expect(RBrace)
    m.complete(p, ForeignBlock)
}

/**
 * `macro? package a.b.c`, or `org::a.b`.
 */
func packageHeader(p: P, m: Marker): Unit {
    p.eat(MacroKw)
    p.bump(PackageKw)
    expectNameRef(p)
    if (p.eat(ColonColon)) {
        expectNameRef(p)
    }
    while (p.eat(Dot)) {
        expectNameRef(p)
    }
    m.complete(p, PackageHeader)
}

func importDecl(p: P, m: Marker): Unit {
    p.bump(ImportKw)
    importTree(p)
    m.complete(p, ImportDecl)
}

/**
 * `a.b.c`, `a.b.*`, `a.b.c as d`, `a.{b, c.*}`, `{a, b}`, and with an organization, `org::a.b`, `org::{a, b}`.
 */
func importTree(p: P): Unit {
    let m = p.start()
    if (p.at(LBrace)) {
        importTreeList(p)
        m.complete(p, ImportTree)
        return
    }
    expectNameRef(p)
    var single = true
    while (p.eat(Dot) || p.eat(ColonColon)) {
        if (p.eat(Star)) {
            single = false
            break
        }
        if (p.at(LBrace)) {
            importTreeList(p)
            single = false
            break
        }
        if (!nameRef(p)) {
            p.error("expected a name")
            break
        }
    }
    if (p.at(AsKw)) {
        if (!single) {
            p.error("only a single import can be renamed")
        }
        let a = p.start()
        p.bump(AsKw)
        expectName(p)
        a.complete(p, ImportAlias)
    }
    m.complete(p, ImportTree)
}

func importTreeList(p: P): Unit {
    let m = p.start()
    p.bump(LBrace)
    while (!p.at(RBrace) && !p.atEof()) {
        if (!atName(p, 0)) {
            p.error("expected a name")
            break
        }
        importTree(p)
        if (!p.eat(Comma)) {
            break
        }
    }
    p.expect(RBrace)
    m.complete(p, ImportTreeList)
}

func featuresDirective(p: P, m: Marker): Unit {
    p.bump(FeaturesKw)
    p.bump(LBrace)
    while (atName(p, 0)) {
        nameRef(p)
        while (p.eat(Dot)) {
            expectNameRef(p)
        }
        if (!p.eat(Comma)) {
            break
        }
    }
    p.expect(RBrace)
    m.complete(p, FeaturesDirective)
}

/**
 * `@M(tokens)`, or `@M[attrs]` on the declaration after it.
 */
func macroExpandDecl(p: P, m: Marker, scope: Scope): Unit {
    macroCallHead(p)
    if (p.at(LParen)) {
        macroArgs(p)
    } else if (scope == InParams) {
        param(p, true)
    } else {
        declaration(p, scope)
    }
    m.complete(p, MacroExpandDecl)
}

/**
 * `@Name`, `@!Name`, `@a.b.Name`, each maybe with `[attrs]`.
 */
func macroCallHead(p: P): Unit {
    p.bumpAny()
    expectNameRef(p)
    while (p.at(Dot) && atName(p, 1)) {
        p.bump(Dot)
        nameRef(p)
    }
    if (p.at(LBracket)) {
        let m = p.start()
        p.bump(LBracket)
        balancedTokens(p, LBracket, RBracket)
        p.expect(RBracket)
        m.complete(p, MacroAttr)
    }
}

func macroArgs(p: P): Unit {
    let m = p.start()
    p.bump(LParen)
    balancedTokens(p, LParen, RParen)
    p.expect(RParen)
    m.complete(p, MacroArgs)
}

/**
 * Tokens up to the `close` matching an `open` already consumed, only `open`s and `close`s counted, as the
 * compiler does; `\` escapes the token after it.
 */
func balancedTokens(p: P, open: SyntaxKind, close: SyntaxKind): Unit {
    var depth = 1
    while (!p.atEof()) {
        if (p.at(Backslash)) {
            p.bumpAny()
            p.bumpAny()
            continue
        }
        if (p.at(Hash)) {
            p.error("expected '#' or a quote in a raw string")
        }
        if (p.at(open)) {
            depth++
        } else if (p.at(close)) {
            depth--
            if (depth == 0) {
                return
            }
        }
        p.bumpAny()
    }
}
