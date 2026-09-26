package cjsyntax

import ginkgo.TokenSet
import ginkgo.parsing.*

let TYPE_RECOVERY = TokenSet<SyntaxKind>([Comma, Gt, RParen, RBracket, LBrace, RBrace, Eq, Semicolon, Arrow,
    WhereKw, Amp, LtColon])

/**
 * A type; the kind of its node, `ErrorNode` if there is none.
 */
func typ(p: P): SyntaxKind {
    if (p.at(Question)) {
        let m = p.start()
        p.bump(Question)
        typ(p)
        m.complete(p, OptionType)
        return OptionType
    }
    match (p.current()) {
        case _ where atName(p, 0) => pathType(p)
        case LParen => parenType(p)
        case ThisTypeKw =>
            let m = p.start()
            p.bump(ThisTypeKw)
            m.complete(p, ThisType)
            ThisType
        case VArrayKw =>
            varrayType(p)
            VArrayType
        case _ where p.atAny(PRIM_TYPES) =>
            let m = p.start()
            p.bumpAny()
            m.complete(p, PrimType)
            PrimType
        case _ =>
            p.errRecover("expected a type", TYPE_RECOVERY)
            ErrorNode
    }
}

/**
 * `a.b.C<T>`: dotted segments, each maybe with type arguments.
 */
func pathType(p: P): SyntaxKind {
    let m = p.start()
    pathSegment(p, None)
    while (p.at(Dot) && atName(p, 1)) {
        p.bump(Dot)
        pathSegment(p, None)
    }
    m.complete(p, PathType)
    PathType
}

/**
 * A name with type arguments: sure ones in a type (`restrictions` `None`), guessed ones in an expression.
 */
func pathSegment(p: P, restrictions: ?Restrictions): Unit {
    let m = p.start()
    nameRef(p)
    if (p.at(Lt)) {
        match (restrictions) {
            case None => typeArgList(p)
            case Some(r) => tryTypeArgs(p, r)
        }
    }
    m.complete(p, PathSegment)
}

/**
 * `(A, B)`, `(a: A, b: B)`, `(A)`, `(A, B) -> C`, `() -> C`.
 */
func parenType(p: P): SyntaxKind {
    let m = p.start()
    p.bump(LParen)
    var count = 0
    while (!p.at(RParen) && !p.atEof()) {
        if (atName(p, 0) && p.nthAt(1, Colon)) {
            let n = p.start()
            name(p)
            p.bump(Colon)
            typ(p)
            n.complete(p, NamedType)
        } else if (typ(p) == ErrorNode && !p.at(Comma)) {
            break
        }
        count++
        if (!p.eat(Comma)) {
            break
        }
    }
    p.expect(RParen)
    let kind = if (p.eat(Arrow)) {
        typ(p)
        FuncType
    } else if (count == 1) {
        ParenType
    } else if (count > 1) {
        TupleType
    } else {
        p.error("expected '->'")
        FuncType
    }
    m.complete(p, kind)
    kind
}

/**
 * `VArray<T, $N>`.
 */
func varrayType(p: P): Unit {
    let m = p.start()
    p.bump(VArrayKw)
    if (p.expect(Lt)) {
        typ(p)
        p.expect(Comma)
        p.expect(Dollar)
        if (!p.eat(IntLit)) {
            p.error("expected an integer")
        }
        p.expect(Gt)
    }
    m.complete(p, VArrayType)
}

/**
 * `<A, B>`: how many arguments, and whether all are paths, which is what makes them look like comparisons.
 */
func typeArgList(p: P): (Int64, Bool) {
    let m = p.start()
    p.bump(Lt)
    var count = 0
    var allPaths = true
    while (!p.at(Gt) && !p.atEof()) {
        let kind = typ(p)
        count++
        allPaths = allPaths && kind == PathType
        if (!p.eat(Comma)) {
            break
        }
    }
    if (count == 0) {
        p.error("expected a type argument")
    }
    p.expect(Gt)
    m.complete(p, TypeArgList)
    (count, allPaths)
}

/**
 * Type arguments after a name in an expression or a pattern, if what follows `<` reads as them; `a < b` is left
 * alone otherwise. As the compiler: they must parse, and among comma-separated expressions, two or more arguments
 * that could as well be expressions must be followed by something an expression can go on with, or
 * `f(a < b, c > d)` is two comparisons.
 */
func tryTypeArgs(p: P, r: Restrictions): Bool {
    let confusable = typeArgsLookLikeExpressions(p)
    let snapshot = p.snapshot()
    let (count, _) = typeArgList(p)
    var ok = !p.hasErrorSince(snapshot)
    if (ok && count >= 2 && confusable) {
        if (let Some(closer) <- r.commaCloser) {
            ok = canFollowTypeArgs(p, closer)
        }
    }
    if (!ok) {
        p.rewind(snapshot)
    }
    ok
}

/**
 * Whether the `<...>` here holds nothing but names, dots, commas, and parentheses and angle brackets around them:
 * the compiler's types that "may be confused with expressions".
 */
func typeArgsLookLikeExpressions(p: P): Bool {
    var depth = 0
    var i = 0
    while (true) {
        match (p.nth(i)) {
            case Lt => depth++
            case Gt =>
                depth--
                if (depth == 0) {
                    return true
                }
            case Comma | Dot | LParen | RParen => ()
            case k where k == Ident || k.isContextualKeyword() => ()
            case _ => return false
        }
        i++
    }
    false
}

func canFollowTypeArgs(p: P, closer: SyntaxKind): Bool {
    if (p.at(closer)) {
        return true
    }
    if (p.newlineBefore() && p.atAny([LBrace, Question, LParen, LBracket, Minus])) {
        return false
    }
    if (p.atAny([LParen, LBracket, Comma, Dot, LBrace])) {
        return true
    }
    match (binaryOp(p)) {
        case Some((_, _, precedence)) => precedence > 0
        case None => false
    }
}
