package ginkgo

/**
 * A node named by its kind and range, rowan's `SyntaxNodePtr`: what a result that outlives a tree keeps
 * instead of the node, which would keep the whole tree alive. It means something only against the tree it
 * was made from, or one of the same text, and `toNode` gives the node back from that tree's root.
 */
public struct SyntaxNodePtr<K> <: Equatable<SyntaxNodePtr<K>> & Hashable & ToString where K <: Kind<K> {
    public SyntaxNodePtr(public let kind: K, public let range: TextRange) {}

    public init(node: SyntaxNode<K>) {
        this(node.kind, node.textRange)
    }

    /**
     * The node under `root` of this kind and range. Where nested nodes share both, the innermost one.
     *
     * @throws IllegalArgumentException - if there is none: the pointer was made from another tree
     */
    public func toNode(root: SyntaxNode<K>): SyntaxNode<K> {
        tryToNode(root) ?? throw IllegalArgumentException("no ${kind} at ${range} in ${root}")
    }

    /**
     * As `toNode`, `None` for a tree that has no such node.
     */
    public func tryToNode(root: SyntaxNode<K>): ?SyntaxNode<K> {
        if (!root.textRange.containsRange(range)) {
            return None
        }
        var found = if (root.kind == kind && root.textRange == range) {
            Some(root)
        } else {
            None<SyntaxNode<K>>
        }
        // an empty range may be inside several children at once, the empty ones and the two around them
        for (child in root.children() where child.textRange.containsRange(range)) {
            if (let Some(inner) <- tryToNode(child)) {
                found = inner
            }
        }
        found
    }

    public operator func ==(other: SyntaxNodePtr<K>): Bool {
        kind == other.kind && range == other.range
    }

    public operator func !=(other: SyntaxNodePtr<K>): Bool {
        !(this == other)
    }

    public func hashCode(): Int64 {
        var hasher = DefaultHasher()
        hasher.write(kind.hashCode())
        hasher.write(range.hashCode())
        hasher.finish()
    }

    public func toString(): String {
        "${kind}@${range}"
    }
}

/**
 * A `SyntaxNodePtr` to a node viewed as `N`, rowan's `AstPtr`.
 */
public struct AstPtr<K, N> <: Equatable<AstPtr<K, N>> & Hashable & ToString where K <: Kind<K>, N <: AstNode<K, N> {
    public AstPtr(public let syntax: SyntaxNodePtr<K>) {}

    public init(node: N) {
        this(SyntaxNodePtr(node.syntax))
    }

    /**
     * The node under `root` this points to, as an `N`.
     *
     * @throws IllegalArgumentException - if there is none, or it is no `N`: the pointer was made from another
     * tree
     */
    public func toNode(root: SyntaxNode<K>): N {
        let node = syntax.toNode(root)
        N.cast(node) ?? throw IllegalArgumentException("${node} is no node of its pointer's type")
    }

    public operator func ==(other: AstPtr<K, N>): Bool {
        syntax == other.syntax
    }

    public operator func !=(other: AstPtr<K, N>): Bool {
        syntax != other.syntax
    }

    public func hashCode(): Int64 {
        syntax.hashCode()
    }

    public func toString(): String {
        syntax.toString()
    }
}
