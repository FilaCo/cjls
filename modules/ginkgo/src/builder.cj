package ginkgo

import std.collection.ArrayList

/**
 * A position in a `GreenNodeBuilder`'s output, to wrap what was built since in a node started later: how an
 * operator parser makes `a + b` a node once it has seen the `+`.
 */
public struct Checkpoint {
    Checkpoint(let childIndex: Int64, let depth: Int64) {}
}

/**
 * Builds a green tree top-down: nodes are started and finished around the tokens they contain, in text order.
 */
public class GreenNodeBuilder<K> where K <: Kind<K> {
    let cache: NodeCache<K>
    let parentKinds = ArrayList<K>()
    let parentStarts = ArrayList<Int64>()
    let children = ArrayList<GreenElement<K>>()

    public init() {
        this(NodeCache<K>())
    }

    public init(cache: NodeCache<K>) {
        this.cache = cache
    }

    public func token(kind: K, text: String): Unit {
        children.add(GreenElement.Token(cache.token(kind, text)))
    }

    public func startNode(kind: K): Unit {
        parentKinds.add(kind)
        parentStarts.add(children.size)
    }

    /**
     * @throws IllegalStateException - if no node is open
     */
    public func finishNode(): Unit {
        if (parentKinds.isEmpty()) {
            throw IllegalStateException("finishNode without an open node")
        }
        let last = parentKinds.size - 1
        let kind = parentKinds[last]
        let start = parentStarts[last]
        parentKinds.remove(at: last)
        parentStarts.remove(at: last)
        let nodeChildren = Array<GreenElement<K>>(children.size - start) {i => children[start + i]}
        children.remove(start..children.size)
        children.add(GreenElement.Node(cache.node(kind, nodeChildren)))
    }

    public func checkpoint(): Checkpoint {
        Checkpoint(children.size, parentKinds.size)
    }

    /**
     * Starts a node that begins at `checkpoint`, taking in everything built at this level since.
     *
     * @throws IllegalStateException - if a node opened after `checkpoint` is still open, or one open at it was
     *     finished since
     */
    public func startNodeAt(checkpoint: Checkpoint, kind: K): Unit {
        if (checkpoint.depth != parentKinds.size) {
            throw IllegalStateException("startNodeAt a checkpoint taken at another depth")
        }
        if (checkpoint.childIndex > children.size ||
            (!parentStarts.isEmpty() && checkpoint.childIndex < parentStarts[parentStarts.size - 1])) {
            throw IllegalStateException("startNodeAt a checkpoint outside the open node")
        }
        parentKinds.add(kind)
        parentStarts.add(checkpoint.childIndex)
    }

    /**
     * The root: exactly one node must have been built, and none left open.
     *
     * @throws IllegalStateException - otherwise
     */
    public func finish(): GreenNode<K> {
        if (!parentKinds.isEmpty()) {
            throw IllegalStateException("finish with ${parentKinds.size} node(s) still open")
        }
        if (children.size != 1) {
            throw IllegalStateException("finish with ${children.size} root elements instead of one node")
        }
        match (children[0]) {
            case GreenElement.Node(node) => node
            case GreenElement.Token(_) => throw IllegalStateException("finish with a token at the root")
        }
    }
}
