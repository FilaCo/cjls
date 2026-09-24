package cjsyntax

import ginkgo.parsing.*

let PATTERN_RECOVERY: Array<SyntaxKind> = [Comma, RParen, Pipe, FatArrow, WhereKw, InKw, LArrow, Eq, Colon, RBrace]

func pattern(p: P): Unit {
    match (p.current()) {
        case _ where p.atAny(LITERALS) || p.at(StringStart) || (p.at(Minus) && p.nthAtAny(1, [IntLit, FloatLit])) ||
            (p.at(LParen) && p.nthAt(1, RParen)) =>
            let m = p.start()
            if (p.at(StringStart)) {
                stringLit(p)
            } else if (p.at(LParen)) {
                p.bump(LParen)
                p.bump(RParen)
            } else {
                p.eat(Minus)
                p.bumpAny()
            }
            m.complete(p, LiteralPat)
        case Underscore =>
            let m = p.start()
            p.bump(Underscore)
            if (p.eat(Colon)) {
                typ(p)
                m.complete(p, TypePat)
            } else {
                m.complete(p, WildcardPat)
            }
        case LParen =>
            let m = p.start()
            patternList(p)
            m.complete(p, TuplePat)
        case _ where atName(p, 0) && (p.nthAt(1, LParen) || p.nthAt(1, Lt) || p.nthAt(1, Dot)) => enumPattern(p)
        case _ where atName(p, 0) && p.nthAt(1, Colon) =>
            let m = p.start()
            name(p)
            p.bump(Colon)
            typ(p)
            m.complete(p, TypePat)
        case _ where atName(p, 0) =>
            let m = p.start()
            name(p)
            m.complete(p, BindPat)
        case _ => p.errRecover("expected a pattern", PATTERN_RECOVERY)
    }
}

func patternList(p: P): Unit {
    p.bump(LParen)
    while (!p.at(RParen) && !p.atEof()) {
        let before = p.position
        pattern(p)
        if (!p.eat(Comma)) {
            if (p.position == before) {
                break
            }
            if (!p.at(RParen)) {
                p.error("expected ',' or ')'")
                break
            }
        }
    }
    p.expect(RParen)
}

/**
 * `Some(x)`, `Option<Int64>.None`, `E.A(1, _)`.
 */
func enumPattern(p: P): Unit {
    let m = p.start()
    pathSegment(p, Restrictions.NONE)
    while (p.at(Dot) && atName(p, 1)) {
        p.bump(Dot)
        pathSegment(p, Restrictions.NONE)
    }
    if (p.at(LParen)) {
        patternList(p)
    }
    m.complete(p, EnumPat)
}

/**
 * What `catch` catches: `e: A | B`, `_: A`, `_`.
 */
func catchPattern(p: P): Unit {
    let m = p.start()
    if (!p.eat(Underscore) && !name(p)) {
        p.error("expected a name or '_'")
    }
    if (p.eat(Colon)) {
        typ(p)
        while (p.eat(Pipe)) {
            typ(p)
        }
    }
    m.complete(p, CatchPat)
}
