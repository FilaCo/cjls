package ginkgo

import std.collection.HashMap

/**
 * Interns green elements, so that equal tokens, and equal small nodes, are one object.
 *
 * Most tokens of a file repeat (keywords, punctuation, whitespace), so interning them saves most of the memory a
 * tree takes. Nodes are interned only up to `MAX_CACHED_CHILDREN` children: larger ones rarely repeat, and hashing
 * them is not free. A cache can be shared by several builders, to share elements between versions of a file.
 */
public class NodeCache<K> where K <: Kind<K> {
    static const MAX_CACHED_CHILDREN = 3

    let tokens = HashMap<GreenToken<K>, GreenToken<K>>()
    let nodes = HashMap<GreenNode<K>, GreenNode<K>>()

    public func token(kind: K, text: String): GreenToken<K> {
        let candidate = GreenToken(kind, text)
        match (tokens.get(candidate)) {
            case Some(cached) => cached
            case None =>
                tokens.add(candidate, candidate)
                candidate
        }
    }

    public func node(kind: K, children: Array<GreenElement<K>>): GreenNode<K> {
        let candidate = GreenNode(children, kind)
        if (children.size > MAX_CACHED_CHILDREN) {
            return candidate
        }
        match (nodes.get(candidate)) {
            case Some(cached) => cached
            case None =>
                nodes.add(candidate, candidate)
                candidate
        }
    }
}
