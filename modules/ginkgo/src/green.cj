package ginkgo

/**
 * An immutable leaf: a kind and the exact text it covers, trivia included.
 *
 * Green elements know nothing about where they are, so equal subtrees can be shared, within a tree and between
 * versions of it. Equality is structural.
 */
public class GreenToken<K> <: Equatable<GreenToken<K>> & Hashable & ToString where K <: Kind<K> {
    let structuralHash: Int64

    public GreenToken(public let kind: K, public let text: String) {
        var hasher = DefaultHasher()
        hasher.write(kind.hashCode())
        hasher.write(text)
        structuralHash = hasher.finish()
    }

    /**
     * In UTF-8 bytes.
     */
    public prop textLen: Int64 {
        get() {
            text.size
        }
    }

    public operator func ==(other: GreenToken<K>): Bool {
        refEq(this, other) || (structuralHash == other.structuralHash && kind == other.kind && text == other.text)
    }

    public operator func !=(other: GreenToken<K>): Bool {
        !(this == other)
    }

    public func hashCode(): Int64 {
        structuralHash
    }

    public func toString(): String {
        text
    }
}

/**
 * An immutable inner node: a kind and its children. It covers exactly the text of its children, in order.
 *
 * Changing a tree means building new nodes along the path to the root; everything else is shared.
 */
public class GreenNode<K> <: Equatable<GreenNode<K>> & Hashable & ToString where K <: Kind<K> {
    let elements: Array<GreenElement<K>>
    let offsets: Array<Int64>
    let structuralHash: Int64

    /**
     * In UTF-8 bytes.
     */
    public let textLen: Int64

    public GreenNode(children: Array<GreenElement<K>>, public let kind: K) {
        elements = children.clone()
        offsets = Array<Int64>(children.size, repeat: 0)
        var hasher = DefaultHasher()
        hasher.write(kind.hashCode())
        var len = 0
        for (i in 0..children.size) {
            offsets[i] = len
            len += children[i].textLen
            hasher.write(children[i].hashCode())
        }
        textLen = len
        structuralHash = hasher.finish()
    }

    public prop childCount: Int64 {
        get() {
            elements.size
        }
    }

    /**
     * @throws IndexOutOfBoundsException - if there is no child `index`
     */
    public func child(index: Int64): GreenElement<K> {
        elements[index]
    }

    /**
     * Where child `index` starts, relative to the start of this node.
     *
     * @throws IndexOutOfBoundsException - if there is no child `index`
     */
    public func childOffset(index: Int64): Int64 {
        offsets[index]
    }

    public func children(): Iterator<GreenElement<K>> {
        elements.iterator()
    }

    /**
     * A copy with child `index` replaced.
     */
    public func replaceChild(index: Int64, element: GreenElement<K>): GreenNode<K> {
        spliceChildren(index, index + 1, [element])
    }

    /**
     * A copy with `element` inserted before child `index`; `index` may be `childCount`.
     */
    public func insertChild(index: Int64, element: GreenElement<K>): GreenNode<K> {
        spliceChildren(index, index, [element])
    }

    /**
     * A copy without child `index`.
     */
    public func removeChild(index: Int64): GreenNode<K> {
        spliceChildren(index, index + 1, [])
    }

    /**
     * A copy with children `start` up to, not including, `end` replaced by `replacement`.
     */
    public func spliceChildren(start: Int64, end: Int64, replacement: Array<GreenElement<K>>): GreenNode<K> {
        if (start < 0 || end < start || end > elements.size) {
            throw IndexOutOfBoundsException("Invalid child range ${start}..${end} of ${elements.size} children")
        }
        GreenNode(elements[..start].concat(replacement).concat(elements[end..]), kind)
    }

    func writeTo(sb: StringBuilder): Unit {
        for (element in elements) {
            match (element) {
                case GreenElement.Node(node) => node.writeTo(sb)
                case GreenElement.Token(token) => sb.append(token.text)
            }
        }
    }

    public operator func ==(other: GreenNode<K>): Bool {
        if (refEq(this, other)) {
            return true
        }
        if (structuralHash != other.structuralHash || kind != other.kind || elements.size != other.elements.size) {
            return false
        }
        for (i in 0..elements.size) {
            if (elements[i] != other.elements[i]) {
                return false
            }
        }
        true
    }

    public operator func !=(other: GreenNode<K>): Bool {
        !(this == other)
    }

    public func hashCode(): Int64 {
        structuralHash
    }

    /**
     * The text this node covers.
     */
    public func toString(): String {
        let sb = StringBuilder()
        writeTo(sb)
        sb.toString()
    }
}

public enum GreenElement<K> <: Equatable<GreenElement<K>> & Hashable & ToString where K <: Kind<K> {
    | Node(GreenNode<K>)
    | Token(GreenToken<K>)

    public prop kind: K {
        get() {
            match (this) {
                case Node(node) => node.kind
                case Token(token) => token.kind
            }
        }
    }

    public prop textLen: Int64 {
        get() {
            match (this) {
                case Node(node) => node.textLen
                case Token(token) => token.textLen
            }
        }
    }

    public func asNode(): ?GreenNode<K> {
        match (this) {
            case Node(node) => node
            case Token(_) => None
        }
    }

    public func asToken(): ?GreenToken<K> {
        match (this) {
            case Node(_) => None
            case Token(token) => token
        }
    }

    public operator func ==(other: GreenElement<K>): Bool {
        match ((this, other)) {
            case (Node(a), Node(b)) => a == b
            case (Token(a), Token(b)) => a == b
            case _ => false
        }
    }

    public operator func !=(other: GreenElement<K>): Bool {
        !(this == other)
    }

    public func hashCode(): Int64 {
        match (this) {
            case Node(node) => node.hashCode()
            case Token(token) => token.hashCode()
        }
    }

    public func toString(): String {
        match (this) {
            case Node(node) => node.toString()
            case Token(token) => token.text
        }
    }
}
