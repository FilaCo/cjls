package ginkgo

/**
 * A node of a tree in place: its green node, plus where it is, in the tree and in the text.
 *
 * These are created as a tree is walked, from its root down, and cost next to nothing; two values for the same
 * node are equal. A tree never changes: editing one builds new green nodes up to a new root.
 */
public class SyntaxNode<K> <: Equatable<SyntaxNode<K>> & Hashable & ToString where K <: Kind<K> {
    /**
     * @param indexInParent - among the parent's children, tokens included
     */
    SyntaxNode(public let green: GreenNode<K>, public let parent: ?SyntaxNode<K>, public let indexInParent: Int64,
        let offset: Int64) {}

    public static func newRoot(green: GreenNode<K>): SyntaxNode<K> {
        SyntaxNode(green, None, 0, 0)
    }

    public prop kind: K {
        get() {
            green.kind
        }
    }

    public prop textRange: TextRange {
        get() {
            TextRange(offset, offset + green.textLen)
        }
    }

    public func text(): String {
        green.toString()
    }

    public func root(): SyntaxNode<K> {
        var node = this
        while (let Some(p) <- node.parent) {
            node = p
        }
        node
    }

    func element(i: Int64): SyntaxElement<K> {
        let at = offset + green.childOffset(i)
        match (green.child(i)) {
            case GreenElement.Node(n) => SyntaxElement.Node(SyntaxNode(n, this, i, at))
            case GreenElement.Token(t) => SyntaxElement.Token(SyntaxToken(t, this, i, at))
        }
    }

    func elementAt(i: Int64): ?SyntaxElement<K> {
        if (0 <= i && i < green.childCount) {
            element(i)
        } else {
            None
        }
    }

    /**
     * The first child node at `from` or after it (before it for `Prev`).
     */
    func nodeFrom(from: Int64, direction: Direction): ?SyntaxNode<K> {
        let step = direction.step()
        var i = from
        while (0 <= i && i < green.childCount) {
            if (let GreenElement.Node(n) <- green.child(i)) {
                return SyntaxNode(n, this, i, offset + green.childOffset(i))
            }
            i += step
        }
        None
    }

    public func childrenWithTokens(): Iterator<SyntaxElement<K>> {
        childrenWithTokens(Next)
    }

    /**
     * The children, tokens included, from the first for `Next`, from the last for `Prev`.
     */
    func childrenWithTokens(direction: Direction): Iterator<SyntaxElement<K>> {
        let first = match (direction) {
            case Next => firstChildOrToken()
            case Prev => lastChildOrToken()
        }
        Successors<SyntaxElement<K>>(first, {el => el.siblingOrToken(direction)})
    }

    public func children(): Iterator<SyntaxNode<K>> {
        Successors<SyntaxNode<K>>(firstChild(), {n => n.nextSibling()})
    }

    public func firstChild(): ?SyntaxNode<K> {
        nodeFrom(0, Next)
    }

    public func lastChild(): ?SyntaxNode<K> {
        nodeFrom(green.childCount - 1, Prev)
    }

    public func firstChildOrToken(): ?SyntaxElement<K> {
        elementAt(0)
    }

    public func lastChildOrToken(): ?SyntaxElement<K> {
        elementAt(green.childCount - 1)
    }

    public func nextSibling(): ?SyntaxNode<K> {
        sibling(Next)
    }

    public func prevSibling(): ?SyntaxNode<K> {
        sibling(Prev)
    }

    func sibling(direction: Direction): ?SyntaxNode<K> {
        parent.flatMap {p => p.nodeFrom(indexInParent + direction.step(), direction)}
    }

    public func nextSiblingOrToken(): ?SyntaxElement<K> {
        parent.flatMap {p => p.elementAt(indexInParent + 1)}
    }

    public func prevSiblingOrToken(): ?SyntaxElement<K> {
        parent.flatMap {p => p.elementAt(indexInParent - 1)}
    }

    /**
     * This node, then its sibling nodes in `direction`.
     */
    public func siblings(direction: Direction): Iterator<SyntaxNode<K>> {
        Successors<SyntaxNode<K>>(this, {n => n.sibling(direction)})
    }

    /**
     * This node, then its siblings in `direction`, tokens included.
     */
    public func siblingsWithTokens(direction: Direction): Iterator<SyntaxElement<K>> {
        SyntaxElement.Node(this).siblingsWithTokens(direction)
    }

    /**
     * This node, then its parent, and so on up to the root.
     */
    public func ancestors(): Iterator<SyntaxNode<K>> {
        Successors<SyntaxNode<K>>(this, {n => n.parent})
    }

    public func preorder(): Iterator<WalkEvent<SyntaxNode<K>>> {
        Preorder(this)
    }

    public func preorderWithTokens(): Iterator<WalkEvent<SyntaxElement<K>>> {
        PreorderWithTokens(this)
    }

    /**
     * This node and every node under it, in preorder.
     */
    public func descendants(): Iterator<SyntaxNode<K>> {
        entered(preorder())
    }

    /**
     * This node and every node and token under it, in preorder.
     */
    public func descendantsWithTokens(): Iterator<SyntaxElement<K>> {
        entered(preorderWithTokens())
    }

    /**
     * The first token under this node, skipping nodes that have none.
     */
    public func firstToken(): ?SyntaxToken<K> {
        edgeToken(Next)
    }

    /**
     * The last token under this node, skipping nodes that have none.
     */
    public func lastToken(): ?SyntaxToken<K> {
        edgeToken(Prev)
    }

    /**
     * The first token under this node for `Next`, the last for `Prev`.
     */
    func edgeToken(direction: Direction): ?SyntaxToken<K> {
        childrenWithTokens(direction).filterMap {
            el => match (el) {
                case SyntaxElement.Token(t) => t
                case SyntaxElement.Node(n) => n.edgeToken(direction)
            }
        }.next()
    }

    /**
     * The token `offset` is inside of, or the two it is between; `NoToken` if it is outside this node.
     */
    public func tokenAtOffset(offset: Int64): TokenAtOffset<SyntaxToken<K>> {
        if (!textRange.containsInclusive(offset)) {
            return NoToken
        }
        var left = None<TokenAtOffset<SyntaxToken<K>>>
        for (i in 0..green.childCount) {
            let child = element(i)
            let range = child.textRange
            if (range.isEmpty() || !range.containsInclusive(offset)) {
                continue
            }
            let found = match (child) {
                case SyntaxElement.Token(t) => Single(t)
                case SyntaxElement.Node(n) => n.tokenAtOffset(offset)
            }
            match (left) {
                case None => left = found
                case Some(l) => match ((l.rightBiased(), found.leftBiased())) {
                    case (Some(a), Some(b)) => return Between(a, b)
                    case _ => return l
                }
            }
        }
        left ?? NoToken
    }

    /**
     * The child, node or token, whose range contains `range`.
     */
    public func childOrTokenAtRange(range: TextRange): ?SyntaxElement<K> {
        for (i in 0..green.childCount) {
            let childRange = TextRange.at(offset + green.childOffset(i), green.child(i).textLen)
            if (childRange.containsRange(range)) {
                return element(i)
            }
        }
        None
    }

    /**
     * The deepest element whose range contains `range`: this node, if no child does.
     *
     * @throws IllegalArgumentException - if `range` is not inside this node
     */
    public func coveringElement(range: TextRange): SyntaxElement<K> {
        if (!textRange.containsRange(range)) {
            throw IllegalArgumentException("${range} is outside ${textRange}")
        }
        var current = SyntaxElement.Node(this)
        while (let SyntaxElement.Node(n) <- current) {
            match (n.childOrTokenAtRange(range)) {
                case Some(child) => current = child
                case None => break
            }
        }
        current
    }

    /**
     * The root of a new tree, the same as this one but for this node, which `replacement` takes the place of.
     */
    public func replaceWith(replacement: GreenNode<K>): GreenNode<K> {
        match (parent) {
            case None => replacement
            case Some(p) => p.replaceWith(p.green.replaceChild(indexInParent, GreenElement.Node(replacement)))
        }
    }

    /**
     * One line per node and token, indented by depth: `Kind@start..end`, then a token's text, escaped.
     */
    public func debugDump(): String {
        let sb = StringBuilder()
        var depth = 0
        for (event in preorderWithTokens()) {
            match (event) {
                case Enter(SyntaxElement.Node(n)) =>
                    sb.append("  " * depth)
                    sb.append("${n.kind}@${n.textRange}\n")
                    depth++
                case Enter(SyntaxElement.Token(t)) =>
                    sb.append("  " * depth)
                    sb.append("${t.kind}@${t.textRange} \"${escape(t.text())}\"\n")
                case Leave(SyntaxElement.Node(_)) => depth--
                case Leave(SyntaxElement.Token(_)) => ()
            }
        }
        sb.toString()
    }

    public operator func ==(other: SyntaxNode<K>): Bool {
        refEq(this, other) || (refEq(green, other.green) && offset == other.offset && indexInParent == other.indexInParent)
    }

    public operator func !=(other: SyntaxNode<K>): Bool {
        !(this == other)
    }

    public func hashCode(): Int64 {
        var hasher = DefaultHasher()
        hasher.write(offset)
        hasher.write(indexInParent)
        hasher.write(green.hashCode())
        hasher.finish()
    }

    /**
     * The text this node covers.
     */
    public func toString(): String {
        text()
    }
}

/**
 * A token of a tree in place: its green token, plus where it is. See `SyntaxNode`.
 */
public class SyntaxToken<K> <: Equatable<SyntaxToken<K>> & Hashable & ToString where K <: Kind<K> {
    SyntaxToken(public let green: GreenToken<K>, public let parent: SyntaxNode<K>, public let indexInParent: Int64,
        let offset: Int64) {}

    public prop kind: K {
        get() {
            green.kind
        }
    }

    public prop textRange: TextRange {
        get() {
            TextRange(offset, offset + green.textLen)
        }
    }

    public func text(): String {
        green.text
    }

    public func nextSiblingOrToken(): ?SyntaxElement<K> {
        parent.elementAt(indexInParent + 1)
    }

    public func prevSiblingOrToken(): ?SyntaxElement<K> {
        parent.elementAt(indexInParent - 1)
    }

    /**
     * This token, then its siblings in `direction`, nodes included.
     */
    public func siblingsWithTokens(direction: Direction): Iterator<SyntaxElement<K>> {
        SyntaxElement.Token(this).siblingsWithTokens(direction)
    }

    /**
     * The parent, then its parent, and so on up to the root.
     */
    public func ancestors(): Iterator<SyntaxNode<K>> {
        parent.ancestors()
    }

    /**
     * The token after this one in the text, wherever in the tree it is.
     */
    public func nextToken(): ?SyntaxToken<K> {
        adjacentToken(Next)
    }

    /**
     * The token before this one in the text, wherever in the tree it is.
     */
    public func prevToken(): ?SyntaxToken<K> {
        adjacentToken(Prev)
    }

    func adjacentToken(direction: Direction): ?SyntaxToken<K> {
        var current = SyntaxElement.Token(this)
        while (true) {
            match (current.siblingOrToken(direction)) {
                case Some(SyntaxElement.Token(t)) => return t
                case Some(SyntaxElement.Node(n)) => match (n.edgeToken(direction)) {
                    case Some(t) => return t
                    case None => current = SyntaxElement.Node(n)
                }
                case None => match (current.parent) {
                    case Some(p) => current = SyntaxElement.Node(p)
                    case None => return None
                }
            }
        }
        None
    }

    /**
     * The root of a new tree, the same as this one but for this token, which `replacement` takes the place of.
     */
    public func replaceWith(replacement: GreenToken<K>): GreenNode<K> {
        parent.replaceWith(parent.green.replaceChild(indexInParent, GreenElement.Token(replacement)))
    }

    public operator func ==(other: SyntaxToken<K>): Bool {
        refEq(this, other) || (refEq(green, other.green) && offset == other.offset && indexInParent == other.indexInParent &&
            parent == other.parent)
    }

    public operator func !=(other: SyntaxToken<K>): Bool {
        !(this == other)
    }

    public func hashCode(): Int64 {
        var hasher = DefaultHasher()
        hasher.write(offset)
        hasher.write(indexInParent)
        hasher.write(green.hashCode())
        hasher.finish()
    }

    public func toString(): String {
        green.text
    }
}

public enum SyntaxElement<K> <: Equatable<SyntaxElement<K>> & Hashable & ToString where K <: Kind<K> {
    | Node(SyntaxNode<K>)
    | Token(SyntaxToken<K>)

    public prop kind: K {
        get() {
            match (this) {
                case SyntaxElement.Node(n) => n.kind
                case SyntaxElement.Token(t) => t.kind
            }
        }
    }

    public prop textRange: TextRange {
        get() {
            match (this) {
                case SyntaxElement.Node(n) => n.textRange
                case SyntaxElement.Token(t) => t.textRange
            }
        }
    }

    /**
     * `None` only for the root.
     */
    public prop parent: ?SyntaxNode<K> {
        get() {
            match (this) {
                case SyntaxElement.Node(n) => n.parent
                case SyntaxElement.Token(t) => t.parent
            }
        }
    }

    public func asNode(): ?SyntaxNode<K> {
        match (this) {
            case SyntaxElement.Node(n) => n
            case SyntaxElement.Token(_) => None
        }
    }

    public func asToken(): ?SyntaxToken<K> {
        match (this) {
            case SyntaxElement.Node(_) => None
            case SyntaxElement.Token(t) => t
        }
    }

    public func nextSiblingOrToken(): ?SyntaxElement<K> {
        match (this) {
            case SyntaxElement.Node(n) => n.nextSiblingOrToken()
            case SyntaxElement.Token(t) => t.nextSiblingOrToken()
        }
    }

    public func prevSiblingOrToken(): ?SyntaxElement<K> {
        match (this) {
            case SyntaxElement.Node(n) => n.prevSiblingOrToken()
            case SyntaxElement.Token(t) => t.prevSiblingOrToken()
        }
    }

    func siblingOrToken(direction: Direction): ?SyntaxElement<K> {
        match (direction) {
            case Next => nextSiblingOrToken()
            case Prev => prevSiblingOrToken()
        }
    }

    /**
     * This element, then its siblings in `direction`, tokens included.
     */
    func siblingsWithTokens(direction: Direction): Iterator<SyntaxElement<K>> {
        Successors<SyntaxElement<K>>(this, {el => el.siblingOrToken(direction)})
    }

    public operator func ==(other: SyntaxElement<K>): Bool {
        match ((this, other)) {
            case (SyntaxElement.Node(a), SyntaxElement.Node(b)) => a == b
            case (SyntaxElement.Token(a), SyntaxElement.Token(b)) => a == b
            case _ => false
        }
    }

    public operator func !=(other: SyntaxElement<K>): Bool {
        !(this == other)
    }

    public func hashCode(): Int64 {
        match (this) {
            case SyntaxElement.Node(n) => n.hashCode()
            case SyntaxElement.Token(t) => t.hashCode()
        }
    }

    public func toString(): String {
        match (this) {
            case SyntaxElement.Node(n) => n.text()
            case SyntaxElement.Token(t) => t.text()
        }
    }
}

class Preorder<K> <: Iterator<WalkEvent<SyntaxNode<K>>> where K <: Kind<K> {
    var upcoming: ?WalkEvent<SyntaxNode<K>>

    Preorder(let start: SyntaxNode<K>) {
        upcoming = Enter(start)
    }

    public func next(): ?WalkEvent<SyntaxNode<K>> {
        let current = upcoming ?? return None
        upcoming = match (current) {
            case Enter(n) => match (n.firstChild()) {
                case Some(child) => Enter(child)
                case None => Leave(n)
            }
            case Leave(n) where n == start => None
            case Leave(n) => match (n.nextSibling()) {
                case Some(sibling) => Enter(sibling)
                case None => match (n.parent) {
                    case Some(p) => Leave(p)
                    case None => None
                }
            }
        }
        current
    }
}

class PreorderWithTokens<K> <: Iterator<WalkEvent<SyntaxElement<K>>> where K <: Kind<K> {
    var upcoming: ?WalkEvent<SyntaxElement<K>>

    PreorderWithTokens(let start: SyntaxNode<K>) {
        upcoming = Enter(SyntaxElement.Node(start))
    }

    public func next(): ?WalkEvent<SyntaxElement<K>> {
        let current = upcoming ?? return None
        upcoming = match (current) {
            case Enter(SyntaxElement.Node(n)) => match (n.firstChildOrToken()) {
                case Some(child) => Enter(child)
                case None => Leave(SyntaxElement.Node(n))
            }
            case Enter(token) => Leave(token)
            case Leave(SyntaxElement.Node(n)) where n == start => None
            case Leave(el) => match (el.nextSiblingOrToken()) {
                case Some(sibling) => Enter(sibling)
                case None => match (el.parent) {
                    case Some(p) => Leave(SyntaxElement.Node(p))
                    case None => None
                }
            }
        }
        current
    }
}

func entered<T>(events: Iterator<WalkEvent<T>>): Iterator<T> {
    events.filterMap {
        event => match (event) {
            case Enter(v) => v
            case Leave(_) => None
        }
    }
}

func escape(text: String): String {
    let sb = StringBuilder()
    for (r in text.runes()) {
        match (r) {
            case '\\' => sb.append("\\\\")
            case '"' => sb.append("\\\"")
            case '\n' => sb.append("\\n")
            case '\r' => sb.append("\\r")
            case '\t' => sb.append("\\t")
            case _ => sb.append(r)
        }
    }
    sb.toString()
}
