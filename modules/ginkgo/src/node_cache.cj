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
        intern(tokens, GreenToken(kind, text))
    }

    public func node(kind: K, children: Array<GreenElement<K>>): GreenNode<K> {
        let candidate = GreenNode(children, kind)
        if (children.size > MAX_CACHED_CHILDREN) {
            candidate
        } else {
            intern(nodes, candidate)
        }
    }
}

/**
 * The element of `table` equal to `candidate`, added first if there is none.
 */
func intern<T>(table: HashMap<T, T>, candidate: T): T where T <: Hashable & Equatable<T> {
    if (let Some(cached) <- table.get(candidate)) {
        return cached
    }
    table.add(candidate, candidate)
    candidate
}
