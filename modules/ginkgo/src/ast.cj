package ginkgo

/**
 * A typed view of a syntax node, rowan's `AstNode`: a struct wrapping a node of one kind, or an enum of such
 * views for a node that may be one of several. Views are generated from the language's grammar; they only read
 * the tree, and a child missing from a tree with errors is `None`, never a failure.
 */
public interface AstNode<K, T> where K <: Kind<K> {
    /**
     * Whether a node of `kind` can be viewed as `T`.
     */
    static func canCast(kind: K): Bool

    static func cast(node: SyntaxNode<K>): ?T

    prop syntax: SyntaxNode<K>
}

/**
 * The first child of `parent` that is a `T`. What generated accessors are made of, like rowan's `support`.
 */
public func astChild<K, T>(parent: SyntaxNode<K>): ?T where K <: Kind<K>, T <: AstNode<K, T> {
    astChildren<K, T>(parent).next()
}

/**
 * The children of `parent` that are `T`s, in order.
 */
public func astChildren<K, T>(parent: SyntaxNode<K>): Iterator<T> where K <: Kind<K>, T <: AstNode<K, T> {
    parent.children().filterMap {c => T.cast(c)}
}

/**
 * Among the children of `parent` whose kind is in `counted`, the one at `n`, if it is a `T`: the second `Expr` of
 * a binary expression, its right side. `counted` holds the kinds of every child that can come before it in the
 * grammar and be taken for it.
 */
public func astNthChild<K, T>(parent: SyntaxNode<K>, n: Int64, counted: TokenSet<K>): ?T where K <: Kind<K>,
    T <: AstNode<K, T> {
    parent.children().filter {c => counted.contains(c.kind)}.skip(n).next().flatMap {c => T.cast(c)}
}

/**
 * The children of `parent` that are `T`s, but for the first `n` of those whose kind is in `counted`: the
 * indices of an index expression, after the expression indexed.
 */
public func astChildrenFrom<K, T>(parent: SyntaxNode<K>, n: Int64, counted: TokenSet<K>): Iterator<T> where K <: Kind<K>,
    T <: AstNode<K, T> {
    SkipCounted<K>(parent.children(), n, counted).filterMap {c => T.cast(c)}
}

class SkipCounted<K> <: Iterator<SyntaxNode<K>> where K <: Kind<K> {
    SkipCounted(let inner: Iterator<SyntaxNode<K>>, var toSkip: Int64, let counted: TokenSet<K>) {}

    public func next(): ?SyntaxNode<K> {
        while (let Some(c) <- inner.next()) {
            if (toSkip > 0 && counted.contains(c.kind)) {
                toSkip--
            } else {
                return c
            }
        }
        None
    }
}

/**
 * The first token of `parent`, not counting those inside its children, whose kind is `kind`.
 */
public func astToken<K>(parent: SyntaxNode<K>, kind: K): ?SyntaxToken<K> where K <: Kind<K> {
    ownTokens(parent).filter {t => t.kind == kind}.next()
}

/**
 * The first token of `parent`, not counting those inside its children, whose kind is in `kinds`: the operator
 * of a binary expression.
 */
public func astToken<K>(parent: SyntaxNode<K>, kinds: TokenSet<K>): ?SyntaxToken<K> where K <: Kind<K> {
    ownTokens(parent).filter {t => kinds.contains(t.kind)}.next()
}

func ownTokens<K>(parent: SyntaxNode<K>): Iterator<SyntaxToken<K>> where K <: Kind<K> {
    parent.childrenWithTokens().filterMap {el => el.asToken()}
}
