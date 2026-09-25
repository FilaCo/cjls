package cjsyntax.ast

import ginkgo.*
import cjsyntax.SyntaxKind

// The accessors `syntax_codegen` leaves out, of children the grammar cannot tell by position alone: each is found
// by the tokens around it instead, as rust-analyzer's `node_ext.rs` does.

let COLON = TokenSet<SyntaxKind>([SyntaxKind.Colon])
let L_PAREN = TokenSet<SyntaxKind>([SyntaxKind.LParen])
let R_PAREN = TokenSet<SyntaxKind>([SyntaxKind.RParen])
let ARROW = TokenSet<SyntaxKind>([SyntaxKind.Arrow])
let CASE = TokenSet<SyntaxKind>([SyntaxKind.CaseKw])
let FAT_ARROW = TokenSet<SyntaxKind>([SyntaxKind.FatArrow])

extend RangeExpr {
    /**
     * What the range starts at: the expression before `..`, if there is one.
     */
    public func start(): ?Expr {
        childBetween<Expr>(node, None, RANGE_EXPR_OP)
    }

    /**
     * What the range ends at: the expression after `..`, if there is one.
     */
    public func end(): ?Expr {
        childBetween<Expr>(node, RANGE_EXPR_OP, COLON)
    }

    /**
     * The step after `:`.
     */
    public func step(): ?Expr {
        childBetween<Expr>(node, COLON, None)
    }
}

extend FuncType {
    /**
     * The types of the parameters, between the parentheses.
     */
    public func types(): Iterator<Type> {
        childrenBetween<Type>(node, L_PAREN, R_PAREN)
    }

    /**
     * The return type, after `->`.
     */
    public func ret(): ?Type {
        childBetween<Type>(node, ARROW, None)
    }
}

extend MatchCase {
    /**
     * The condition of a case in a `match` without a selector.
     */
    public func condition(): ?Expr {
        childBetween<Expr>(node, CASE, FAT_ARROW)
    }

    /**
     * What the case runs, after `=>`.
     */
    public func stmts(): Iterator<Stmt> {
        childrenBetween<Stmt>(node, FAT_ARROW, None)
    }
}

extend SpawnExpr {
    /**
     * The thread context between the parentheses of `spawn (context)`.
     */
    public func context(): ?Expr {
        childBetween<Expr>(node, L_PAREN, R_PAREN)
    }

    /**
     * The lambda the thread runs.
     */
    public func lambda(): ?LambdaExpr {
        if (lParenToken().isSome()) {
            childBetween<LambdaExpr>(node, R_PAREN, None)
        } else {
            astChild<SyntaxKind, LambdaExpr>(node)
        }
    }
}

/**
 * The first `T` among the children of `parent` after its first token in `from`, and before the next one in `to`
 * after that: `None` for the start or the end.
 */
func childBetween<T>(parent: SyntaxNode<SyntaxKind>, from: ?TokenSet<SyntaxKind>, to: ?TokenSet<SyntaxKind>): ?T where T <: AstNode<SyntaxKind,
    T> {
    childrenBetween<T>(parent, from, to).next()
}

/**
 * The `T`s among the children of `parent` after its first token in `from`, and before the next one in `to` after
 * that: `None` for the start or the end.
 */
func childrenBetween<T>(parent: SyntaxNode<SyntaxKind>, from: ?TokenSet<SyntaxKind>, to: ?TokenSet<SyntaxKind>): Iterator<T> where T <: AstNode<SyntaxKind,
    T> {
    Between(parent.childrenWithTokens(), from, to).filterMap {n => T.cast(n)}
}

class Between <: Iterator<SyntaxNode<SyntaxKind>> {
    var started: Bool
    var ended = false

    Between(
        let inner: Iterator<SyntaxElement<SyntaxKind>>,
        let from: ?TokenSet<SyntaxKind>,
        let to: ?TokenSet<SyntaxKind>
    ) {
        started = from.isNone()
    }

    public func next(): ?SyntaxNode<SyntaxKind> {
        while (!ended) {
            match (inner.next()) {
                case None => ended = true
                case Some(SyntaxElement.Token(t)) where !started => started = from?.contains(t.kind) ?? false
                case Some(SyntaxElement.Token(t)) => ended = to?.contains(t.kind) ?? false
                case Some(SyntaxElement.Node(n)) where started => return n
                case Some(SyntaxElement.Node(_)) => ()
            }
        }
        None
    }
}
