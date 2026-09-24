package cjsyntax

import ginkgo.parsing.*

/**
 * The precedence of `..`: operators below it end the initializer of a `let` condition.
 */
const RANGE_PRECEDENCE = 11

/**
 * An expression; false, with nothing consumed, if none starts here. Assignment is allowed at this level only.
 */
func expr(p: P, r: Restrictions): Bool {
    exprBp(p, r, 0, true).isSome()
}

func exprOrError(p: P, r: Restrictions): Unit {
    if (!expr(p, r)) {
        p.error("expected an expression")
    }
}

/**
 * Precedence climbing, as the compiler does it: operators bind while tighter than `precedence`, the one of the
 * operator on the left; `**` and `??` also at equal precedence, being right-associative, and assignment (0) only
 * at the start of an expression (`top`).
 */
func exprBp(p: P, r: Restrictions, precedence: Int64, top: Bool): ?CompletedMarker<SyntaxKind> {
    let lhs = if (r.allowLet && p.at(LetKw)) {
        letExpr(p)
    } else {
        unaryOrPostfix(p, r) ?? return None
    }
    binaryRest(p, r, precedence, top, lhs)
}

func binaryRest(p: P, r: Restrictions, precedence: Int64, top: Bool, first: CompletedMarker<SyntaxKind>): ?CompletedMarker<SyntaxKind> {
    var lhs = first
    while (let Some((op, n, opPrecedence)) <- binaryOp(p)) {
        if (r.allowLet && lhs.kind == LetExpr && opPrecedence < RANGE_PRECEDENCE && op != AmpAmp && op != PipePipe) {
            break
        }
        if (r.letInit && opPrecedence < RANGE_PRECEDENCE) {
            break
        }
        if (precedence > opPrecedence) {
            break
        }
        if (precedence == opPrecedence && op != StarStar && op != QuestionQuestion && !(top && opPrecedence == 0)) {
            if (!top) {
                if (let Some(name) <- nonAssociativeName(opPrecedence)) {
                    p.error("${name} operators cannot be chained")
                }
            }
            break
        }
        let m = lhs.precede(p)
        p.bumpComposite(op, n)
        lhs = match (op) {
            case IsKw =>
                typ(p)
                m.complete(p, IsExpr)
            case AsKw =>
                typ(p)
                m.complete(p, AsExpr)
            case DotDot | DotDotEq =>
                operand(p, r, opPrecedence)
                if (p.eat(Colon)) {
                    operand(p, r, opPrecedence)
                }
                m.complete(p, RangeExpr)
            case _ =>
                operand(p, r, opPrecedence)
                m.complete(p, BinExpr)
        }
    }
    lhs
}

/**
 * The right side of a binary operator: an expression, not a declaration a macro call applies to.
 */
func operand(p: P, r: Restrictions, precedence: Int64): Unit {
    match (exprBp(p, r, precedence, false)) {
        case None => p.error("expected an expression")
        case Some(cm) where cm.kind == MacroExpandDecl => p.error("expected an expression, found a declaration")
        case _ => ()
    }
}

/**
 * The operators the compiler refuses to chain, by precedence: `a < b < c` is an error, not `(a < b) < c`.
 */
func nonAssociativeName(precedence: Int64): ?String {
    match (precedence) {
        case 0 => "assignment"
        case 9 => "equality"
        case 10 => "comparison"
        case 11 => "range"
        case _ => None
    }
}

/**
 * The binary operator here, if any: its kind, how many tokens make it, its precedence (0 for an assignment).
 * `-` and `?` after a newline start the next statement instead.
 */
func binaryOp(p: P): ?(SyntaxKind, Int64, Int64) {
    let k = p.current()
    match (k) {
        case Gt =>
            if (p.atComposite([Gt, Gt, Eq])) {
                (GtGtEq, 3, 0)
            } else if (p.atComposite([Gt, Gt])) {
                (GtGt, 2, 13)
            } else if (p.atComposite([Gt, Eq])) {
                (GtEq, 2, 10)
            } else {
                (Gt, 1, 10)
            }
        case Question where !p.newlineBefore() && p.atComposite([Question, Question]) => (QuestionQuestion, 2, 2)
        case Minus where p.newlineBefore() => None
        case StarStar => (k, 1, 16)
        case Star | Slash | Percent => (k, 1, 15)
        case Plus | Minus => (k, 1, 14)
        case LtLt => (k, 1, 13)
        case DotDot | DotDotEq => (k, 1, RANGE_PRECEDENCE)
        case Lt | LtEq | IsKw | AsKw => (k, 1, 10)
        case EqEq | BangEq => (k, 1, 9)
        case Amp => (k, 1, 8)
        case Caret => (k, 1, 7)
        case Pipe => (k, 1, 6)
        case AmpAmp => (k, 1, 5)
        case PipePipe => (k, 1, 3)
        case PipeGt | TildeGt => (k, 1, 1)
        case Eq | PlusEq | MinusEq | StarEq | StarStarEq | SlashEq | PercentEq | AmpAmpEq | PipePipeEq | AmpEq |
            PipeEq | CaretEq | LtLtEq => (k, 1, 0)
        case _ => None
    }
}

func unaryOrPostfix(p: P, r: Restrictions): ?CompletedMarker<SyntaxKind> {
    if (p.at(Minus) || p.at(Bang)) {
        let m = p.start()
        p.bumpAny()
        match (unaryOrPostfix(p, r.withoutLet())) {
            case None => p.error("expected an expression")
            case Some(cm) where cm.kind == MacroExpandDecl => p.error("expected an expression, found a declaration")
            case _ => ()
        }
        return m.complete(p, UnaryExpr)
    }
    let lhs = atom(p, r) ?? return None
    postfix(p, r, lhs)
}

/**
 * `.name` (a newline may come before the dot), and on the same line: `?`, `[index]`, `(args)`, a trailing
 * lambda; then `++` and `--`.
 */
func postfix(p: P, r: Restrictions, first: CompletedMarker<SyntaxKind>): CompletedMarker<SyntaxKind> {
    var lhs = first
    if (lhs.kind == BreakExpr || lhs.kind == ContinueExpr || lhs.kind == MacroExpandDecl) {
        return lhs
    }
    while (true) {
        if (p.at(Dot)) {
            let m = lhs.precede(p)
            p.bump(Dot)
            expectNameRef(p)
            if (p.at(Lt)) {
                tryTypeArgs(p, r)
            }
            lhs = m.complete(p, MemberAccessExpr)
            continue
        }
        if (p.newlineBefore()) {
            break
        }
        match (p.current()) {
            case Question where p.nthAt(1, Dot) || (!p.nthNewlineBefore(1) && p.nthAtAny(1, [LParen, LBracket, LBrace])) =>
                let m = lhs.precede(p)
                p.bump(Question)
                lhs = m.complete(p, OptionalExpr)
            case LBracket =>
                let m = lhs.precede(p)
                p.bump(LBracket)
                while (!p.at(RBracket) && !p.atEof()) {
                    indexArg(p)
                    if (!p.eat(Comma)) {
                        break
                    }
                }
                p.expect(RBracket)
                lhs = m.complete(p, IndexExpr)
            case LParen =>
                let m = lhs.precede(p)
                argList(p, LParen, RParen, ArgList)
                lhs = m.complete(p, CallExpr)
            case LBrace =>
                let m = lhs.precede(p)
                lambdaExpr(p, true)
                lhs = m.complete(p, TrailingLambdaExpr)
            case At where atBuiltinAnnotation(p) && p.nthAt(2, LBrace) =>
                let m = lhs.precede(p)
                let l = p.start()
                annotations(p)
                lambdaInner(p, l, true)
                lhs = m.complete(p, TrailingLambdaExpr)
            case _ => break
        }
    }
    while ((p.at(PlusPlus) || p.at(MinusMinus)) && !p.newlineBefore()) {
        let m = lhs.precede(p)
        p.bumpAny()
        lhs = m.complete(p, PostfixExpr)
    }
    lhs
}

/**
 * An index, or a range of them: `i`, `a..b`, `a..`, `..b`, `..`, `a..=b : step`.
 */
func indexArg(p: P): Unit {
    let startless = p.at(DotDot) || p.at(DotDotEq)
    let m = p.start()
    if (!startless) {
        let first = exprBp(p, Restrictions.NONE, RANGE_PRECEDENCE, true)
        match (first) {
            case None =>
                m.abandon(p)
                p.error("expected an expression")
                return
            case Some(cm) where !(p.at(DotDot) || p.at(DotDotEq)) =>
                m.abandon(p)
                binaryRest(p, Restrictions.NONE, 0, true, cm)
                return
            case _ => ()
        }
    }
    p.bumpAny()
    if (!p.at(RBracket) && !p.at(Colon) && !p.at(Comma)) {
        exprBp(p, Restrictions.NONE, RANGE_PRECEDENCE, true)
    }
    if (p.eat(Colon)) {
        if (exprBp(p, Restrictions.NONE, RANGE_PRECEDENCE, true).isNone()) {
            p.error("expected an expression")
        }
    }
    m.complete(p, RangeExpr)
}

/**
 * `(a, name: b, inout c)` for a call, `[a, name: b]` for an annotation.
 */
func argList(p: P, open: SyntaxKind, close: SyntaxKind, kind: SyntaxKind): Unit {
    let m = p.start()
    p.bump(open)
    while (!p.at(close) && !p.atEof()) {
        let a = p.start()
        if (atName(p, 0) && p.nthAt(1, Colon)) {
            nameRef(p)
            p.bump(Colon)
        } else {
            p.eat(InoutKw)
        }
        exprOrError(p, Restrictions.commaList(close))
        a.complete(p, Arg)
        if (!p.eat(Comma)) {
            break
        }
    }
    p.expect(close)
    m.complete(p, kind)
}

func atom(p: P, r: Restrictions): ?CompletedMarker<SyntaxKind> {
    match (p.current()) {
        case LParen => parenExpr(p, r)
        case LBracket => arrayExpr(p)
        case LBrace => lambdaExpr(p, false)
        case VArrayKw => varrayExpr(p)
        case QuoteKw => quoteExpr(p)
        case ThisKw => single(p, ThisExpr)
        case SuperKw => single(p, SuperExpr)
        case IfKw => ifExpr(p)
        case TryKw => tryExpr(p)
        case ForKw => forInExpr(p)
        case DoKw => doWhileExpr(p)
        case WhileKw => whileExpr(p)
        case ThrowKw => keywordThenExpr(p, ThrowExpr)
        case ReturnKw => returnExpr(p)
        case ContinueKw => single(p, ContinueExpr)
        case BreakKw => single(p, BreakExpr)
        case MatchKw => matchExpr(p)
        case UnsafeKw where p.nthAt(1, LBrace) =>
            let m = p.start()
            p.bump(UnsafeKw)
            block(p)
            m.complete(p, UnsafeExpr)
        case SpawnKw => spawnExpr(p)
        case SynchronizedKw => synchronizedExpr(p)
        case StringStart => stringLit(p)
        case Underscore => single(p, WildcardExpr)
        case At where atBuiltinAnnotation(p) =>
            let m = p.start()
            annotations(p)
            if (p.at(LBrace)) {
                lambdaInner(p, m, false)
            } else {
                p.error("expected a lambda")
                m.complete(p, LambdaExpr)
            }
        case At | AtBang where atMacroCall(p) => macroExpand(p)
        case _ where p.atAny(LITERALS) => single(p, Literal)
        case _ where p.atAny(PRIM_TYPES) && p.nthAt(1, LParen) =>
            let m = p.start()
            let t = p.start()
            p.bumpAny()
            t.complete(p, PrimType)
            p.bump(LParen)
            exprOrError(p, Restrictions.NONE)
            p.expect(RParen)
            m.complete(p, TypeConvExpr)
        case _ where p.atAny(PRIM_TYPES) && p.nthAt(1, Dot) => single(p, PrimTypeExpr)
        case _ where atName(p, 0) =>
            let m = p.start()
            nameRef(p)
            if (p.at(Lt)) {
                tryTypeArgs(p, r)
            }
            m.complete(p, RefExpr)
        case _ => None
    }
}

/**
 * A node of one token.
 */
func single(p: P, kind: SyntaxKind): CompletedMarker<SyntaxKind> {
    let m = p.start()
    p.bumpAny()
    m.complete(p, kind)
}

func keywordThenExpr(p: P, kind: SyntaxKind): CompletedMarker<SyntaxKind> {
    let m = p.start()
    p.bumpAny()
    exprOrError(p, Restrictions.NONE)
    m.complete(p, kind)
}

/**
 * `()`, `(a)`, `(a, b)`. Inside a condition, the parentheses keep it one: `(let x <- a) && b`.
 */
func parenExpr(p: P, r: Restrictions): CompletedMarker<SyntaxKind> {
    let m = p.start()
    p.bump(LParen)
    if (p.eat(RParen)) {
        return m.complete(p, UnitExpr)
    }
    let inner = Restrictions(r.allowLet, false, RParen)
    exprOrError(p, inner)
    if (!p.at(Comma)) {
        p.expect(RParen)
        return m.complete(p, ParenExpr)
    }
    while (p.eat(Comma)) {
        if (p.at(RParen)) {
            break
        }
        exprOrError(p, inner)
    }
    p.expect(RParen)
    m.complete(p, TupleExpr)
}

func arrayExpr(p: P): CompletedMarker<SyntaxKind> {
    let m = p.start()
    p.bump(LBracket)
    while (!p.at(RBracket) && !p.atEof()) {
        exprOrError(p, Restrictions.commaList(RBracket))
        if (!p.eat(Comma)) {
            break
        }
    }
    p.expect(RBracket)
    m.complete(p, ArrayExpr)
}

func lambdaExpr(p: P, trailing: Bool): CompletedMarker<SyntaxKind> {
    lambdaInner(p, p.start(), trailing)
}

/**
 * `{ a, b: T => stmts }`, `{ => stmts }`, and for a trailing lambda only, `{ stmts }`.
 */
func lambdaInner(p: P, m: Marker, trailing: Bool): CompletedMarker<SyntaxKind> {
    p.bump(LBrace)
    if (p.at(FatArrow)) {
        p.bump(FatArrow)
    } else if ((atName(p, 0) || p.at(Underscore)) && p.nthAtAny(1, [Comma, Colon, FatArrow])) {
        let list = p.start()
        while (atName(p, 0) || p.at(Underscore)) {
            let param = p.start()
            if (!p.eat(Underscore)) {
                name(p)
            }
            if (p.eat(Colon)) {
                typ(p)
            }
            param.complete(p, LambdaParam)
            if (!p.eat(Comma)) {
                break
            }
        }
        list.complete(p, LambdaParamList)
        p.expect(FatArrow)
    } else if (!trailing) {
        p.error("expected '=>' in a lambda")
    }
    statements(p, [RBrace])
    p.expect(RBrace)
    m.complete(p, LambdaExpr)
}

func block(p: P): Unit {
    let m = p.start()
    p.bump(LBrace)
    statements(p, [RBrace])
    p.expect(RBrace)
    m.complete(p, Block)
}

func blockOrError(p: P): Unit {
    if (p.at(LBrace)) {
        block(p)
    } else {
        p.error("expected '{'")
    }
}

/**
 * Expressions and declarations up to one of `terminators`, separated by newlines or `;`.
 */
func statements(p: P, terminators: Array<SyntaxKind>): Unit {
    var needSeparator = false
    while (true) {
        if (p.eat(Semicolon)) {
            needSeparator = false
            continue
        }
        if (p.atAny(terminators) || p.atEof()) {
            return
        }
        if (needSeparator && !p.newlineBefore()) {
            p.error("expected a newline or ';'")
        }
        statement(p, terminators)
        needSeparator = true
    }
}

func statement(p: P, terminators: Array<SyntaxKind>): Unit {
    if (!atContextualKeywordAsName(p) && !atMacroCall(p) && atDeclStart(p)) {
        declaration(p, InBlock)
    } else if (!expr(p, Restrictions.NONE)) {
        skipToLineEnd(p, "expected an expression or a declaration", terminators)
    }
}

/**
 * `@M(tokens)` is an expression; `@M[attrs]` without arguments applies to what follows: another macro call,
 * which it is as much an expression as, or a declaration, which the compiler checks against no scope here.
 */
func macroExpand(p: P): CompletedMarker<SyntaxKind> {
    let m = p.start()
    macroCallHead(p)
    if (p.at(LParen)) {
        macroArgs(p)
        m.complete(p, MacroExpandExpr)
    } else if (atMacroCall(p)) {
        let inner = macroExpand(p)
        m.complete(p, inner.kind)
    } else {
        declaration(p, InMacroInput)
        m.complete(p, MacroExpandDecl)
    }
}

/**
 * `"text ${expr} text"`: the lexer has cut it into pieces.
 */
func stringLit(p: P): CompletedMarker<SyntaxKind> {
    let m = p.start()
    p.bump(StringStart)
    while (true) {
        match (p.current()) {
            case StringContent => p.bump(StringContent)
            case InterpolationStart =>
                let i = p.start()
                p.bump(InterpolationStart)
                statements(p, [InterpolationEnd, StringEnd, StringContent])
                p.eat(InterpolationEnd)
                i.complete(p, Interpolation)
            case StringEnd =>
                p.bump(StringEnd)
                break
            case _ => break
        }
    }
    m.complete(p, StringLit)
}

/**
 * `let pattern | pattern <- expr`, in a condition.
 */
func letExpr(p: P): CompletedMarker<SyntaxKind> {
    let m = p.start()
    p.bump(LetKw)
    pattern(p)
    while (p.eat(Pipe)) {
        pattern(p)
    }
    if (p.expect(LArrow)) {
        if (exprBp(p, Restrictions(false, true, None), 0, true).isNone()) {
            p.error("expected an expression")
        }
    }
    m.complete(p, LetExpr)
}

func condition(p: P, r: Restrictions): Unit {
    if (p.expect(LParen)) {
        exprOrError(p, r)
        p.expect(RParen)
    }
}

func ifExpr(p: P): CompletedMarker<SyntaxKind> {
    let m = p.start()
    p.bump(IfKw)
    condition(p, Restrictions.CONDITION)
    blockOrError(p)
    if (p.eat(ElseKw)) {
        if (p.at(IfKw)) {
            ifExpr(p)
        } else {
            blockOrError(p)
        }
    }
    m.complete(p, IfExpr)
}

func whileExpr(p: P): CompletedMarker<SyntaxKind> {
    let m = p.start()
    p.bump(WhileKw)
    condition(p, Restrictions.CONDITION)
    blockOrError(p)
    m.complete(p, WhileExpr)
}

func doWhileExpr(p: P): CompletedMarker<SyntaxKind> {
    let m = p.start()
    p.bump(DoKw)
    blockOrError(p)
    if (p.expect(WhileKw)) {
        condition(p, Restrictions.NONE)
    }
    m.complete(p, DoWhileExpr)
}

func forInExpr(p: P): CompletedMarker<SyntaxKind> {
    let m = p.start()
    p.bump(ForKw)
    if (p.expect(LParen)) {
        pattern(p)
        if (p.expect(InKw)) {
            exprOrError(p, Restrictions.NONE)
        }
        if (p.at(WhereKw)) {
            guard(p)
        }
        p.expect(RParen)
    }
    blockOrError(p)
    m.complete(p, ForInExpr)
}

func guard(p: P): Unit {
    let m = p.start()
    p.bump(WhereKw)
    exprOrError(p, Restrictions.NONE)
    m.complete(p, Guard)
}

func tryExpr(p: P): CompletedMarker<SyntaxKind> {
    let m = p.start()
    p.bump(TryKw)
    if (p.at(LParen)) {
        let list = p.start()
        p.bump(LParen)
        while (!p.at(RParen) && !p.atEof()) {
            let res = p.start()
            expectName(p)
            if (p.eat(Colon)) {
                typ(p)
            }
            if (p.expect(Eq)) {
                exprOrError(p, Restrictions.commaList(RParen))
            }
            res.complete(p, ResourceDecl)
            if (!p.eat(Comma)) {
                break
            }
        }
        p.expect(RParen)
        list.complete(p, ResourceList)
    }
    blockOrError(p)
    while (p.at(CatchKw)) {
        let c = p.start()
        p.bump(CatchKw)
        if (p.expect(LParen)) {
            catchPattern(p)
            p.expect(RParen)
        }
        blockOrError(p)
        c.complete(p, CatchClause)
    }
    if (p.at(FinallyKw)) {
        let f = p.start()
        p.bump(FinallyKw)
        blockOrError(p)
        f.complete(p, FinallyClause)
    }
    m.complete(p, TryExpr)
}

/**
 * `match (x) { case p | q where g => ... }`, or without a selector, `match { case cond => ... }`.
 */
func matchExpr(p: P): CompletedMarker<SyntaxKind> {
    let m = p.start()
    p.bump(MatchKw)
    let hasSelector = p.at(LParen)
    if (hasSelector) {
        p.bump(LParen)
        exprOrError(p, Restrictions.NONE)
        p.expect(RParen)
    }
    if (p.at(LBrace)) {
        let body = p.start()
        p.bump(LBrace)
        while (true) {
            while (p.eat(Semicolon)) {}
            if (p.at(RBrace) || p.atEof()) {
                break
            }
            if (p.at(CaseKw)) {
                matchCase(p, hasSelector)
            } else {
                skipToLineEnd(p, "expected 'case'", [RBrace, CaseKw])
            }
        }
        p.expect(RBrace)
        body.complete(p, MatchBody)
    } else {
        p.error("expected '{'")
    }
    m.complete(p, MatchExpr)
}

func matchCase(p: P, hasSelector: Bool): Unit {
    let m = p.start()
    p.bump(CaseKw)
    if (hasSelector) {
        pattern(p)
        while (p.eat(Pipe)) {
            pattern(p)
        }
        if (p.at(WhereKw)) {
            guard(p)
        }
    } else if (p.at(Underscore) && p.nthAt(1, FatArrow)) {
        single(p, WildcardExpr)
    } else {
        exprOrError(p, Restrictions.NONE)
    }
    p.expect(FatArrow)
    let bodyStart = p.position
    statements(p, [CaseKw, RBrace])
    if (p.position == bodyStart) {
        p.error("a match case cannot be empty")
    }
    m.complete(p, MatchCase)
}

/**
 * `return` takes a value unless what follows cannot start one, a newline notwithstanding, as in the compiler.
 */
func returnExpr(p: P): CompletedMarker<SyntaxKind> {
    let m = p.start()
    p.bump(ReturnKw)
    let noValue = (atDeclStart(p) && !isContextualKeyword(p.current())) ||
        p.atAny([Semicolon, Comma, RParen, RBracket, RBrace, CaseKw, FatArrow, InterpolationEnd]) || p.atEof()
    if (!noValue) {
        exprOrError(p, Restrictions.NONE)
    }
    m.complete(p, ReturnExpr)
}

func spawnExpr(p: P): CompletedMarker<SyntaxKind> {
    let m = p.start()
    p.bump(SpawnKw)
    if (p.eat(LParen)) {
        exprOrError(p, Restrictions.NONE)
        p.expect(RParen)
    }
    if (atBuiltinAnnotation(p)) {
        let l = p.start()
        annotations(p)
        if (p.at(LBrace)) {
            lambdaInner(p, l, true)
        } else {
            l.complete(p, LambdaExpr)
            p.error("expected a lambda")
        }
    } else if (p.at(LBrace)) {
        lambdaExpr(p, true)
    } else {
        p.error("expected a lambda")
    }
    m.complete(p, SpawnExpr)
}

func synchronizedExpr(p: P): CompletedMarker<SyntaxKind> {
    let m = p.start()
    p.bump(SynchronizedKw)
    condition(p, Restrictions.NONE)
    blockOrError(p)
    m.complete(p, SynchronizedExpr)
}

/**
 * `VArray<T, $N>(args)`.
 */
func varrayExpr(p: P): CompletedMarker<SyntaxKind> {
    let m = p.start()
    varrayType(p)
    if (p.at(LParen)) {
        argList(p, LParen, RParen, ArgList)
    }
    m.complete(p, VArrayExpr)
}

/**
 * `quote(tokens)`: the tokens are kept as they are, but for `$(expr)`, parsed; `\` escapes the token after it.
 */
func quoteExpr(p: P): CompletedMarker<SyntaxKind> {
    let m = p.start()
    p.bump(QuoteKw)
    if (p.expect(LParen)) {
        var depth = 1
        while (!p.atEof()) {
            if (p.at(Backslash)) {
                p.bumpAny()
                p.bumpAny()
                continue
            }
            if (p.at(Dollar) && !p.nthAt(1, LParen)) {
                p.error("expected a name or '(' after '$'")
            } else if (p.at(Dollar)) {
                let i = p.start()
                p.bump(Dollar)
                p.bump(LParen)
                exprOrError(p, Restrictions.NONE)
                p.expect(RParen)
                i.complete(p, QuoteInterpolation)
                continue
            }
            if (p.at(LParen)) {
                depth++
            } else if (p.at(RParen)) {
                depth--
                if (depth == 0) {
                    break
                }
            }
            p.bumpAny()
        }
        p.expect(RParen)
    }
    m.complete(p, QuoteExpr)
}
