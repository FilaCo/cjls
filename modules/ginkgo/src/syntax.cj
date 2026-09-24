package ginkgo

/**
 * A node of a tree in place: its green node, plus where it is, in the tree and in the text.
 *
 * These are created as a tree is walked, from its root down, and cost next to nothing; two values for the same
 * node are equal. A tree never changes: editing one builds new green nodes up to a new root.
 */
public class SyntaxNode<K> <: Equatable<SyntaxNode<K>> & Hashable & ToString where K <: Kind<K> {
    let greenNode: GreenNode<K>
    let parentNode: ?SyntaxNode<K>
    let index: Int64
    let offset: Int64

    init(green: GreenNode<K>, parent: ?SyntaxNode<K>, index: Int64, offset: Int64) {
        this.greenNode = green
        this.parentNode = parent
        this.index = index
        this.offset = offset
    }

    public static func newRoot(green: GreenNode<K>): SyntaxNode<K> {
        SyntaxNode(green, None, 0, 0)
    }

    public prop kind: K {
        get() {
            greenNode.kind
        }
    }

    public prop green: GreenNode<K> {
        get() {
            greenNode
        }
    }

    public prop parent: ?SyntaxNode<K> {
        get() {
            parentNode
        }
    }

    /**
     * Among the parent's children, tokens included.
     */
    public prop indexInParent: Int64 {
        get() {
            index
        }
    }

    public prop textRange: TextRange {
        get() {
            TextRange(offset, offset + greenNode.textLen)
        }
    }

    public func text(): String {
        greenNode.toString()
    }

    public func root(): SyntaxNode<K> {
        var node = this
        while (let Some(p) <- node.parentNode) {
            node = p
        }
        node
    }

    func element(i: Int64): SyntaxElement<K> {
        let at = offset + greenNode.childOffset(i)
        match (greenNode.child(i)) {
            case GreenElement.Node(n) => SyntaxElement.Node(SyntaxNode(n, this, i, at))
            case GreenElement.Token(t) => SyntaxElement.Token(SyntaxToken(t, this, i, at))
        }
    }

    func elementAt(i: Int64): ?SyntaxElement<K> {
        if (0 <= i && i < greenNode.childCount) {
            element(i)
        } else {
            None
        }
    }

    /**
     * The first child node at `from` or after it (before it for `Prev`).
     */
    func nodeFrom(from: Int64, direction: Direction): ?SyntaxNode<K> {
        let step = match (direction) {
            case Next => 1
            case Prev => -1
        }
        var i = from
        while (0 <= i && i < greenNode.childCount) {
            if (let GreenElement.Node(n) <- greenNode.child(i)) {
                return SyntaxNode(n, this, i, offset + greenNode.childOffset(i))
            }
            i += step
        }
        None
    }

    public func childrenWithTokens(): Iterator<SyntaxElement<K>> {
        Successors<SyntaxElement<K>>(elementAt(0), {el => el.nextSiblingOrToken()})
    }

    public func children(): Iterator<SyntaxNode<K>> {
        Successors<SyntaxNode<K>>(firstChild(), {n => n.nextSibling()})
    }

    public func firstChild(): ?SyntaxNode<K> {
        nodeFrom(0, Next)
    }

    public func lastChild(): ?SyntaxNode<K> {
        nodeFrom(greenNode.childCount - 1, Prev)
    }

    public func firstChildOrToken(): ?SyntaxElement<K> {
        elementAt(0)
    }

    public func lastChildOrToken(): ?SyntaxElement<K> {
        elementAt(greenNode.childCount - 1)
    }

    public func nextSibling(): ?SyntaxNode<K> {
        match (parentNode) {
            case Some(p) => p.nodeFrom(index + 1, Next)
            case None => None
        }
    }

    public func prevSibling(): ?SyntaxNode<K> {
        match (parentNode) {
            case Some(p) => p.nodeFrom(index - 1, Prev)
            case None => None
        }
    }

    public func nextSiblingOrToken(): ?SyntaxElement<K> {
        match (parentNode) {
            case Some(p) => p.elementAt(index + 1)
            case None => None
        }
    }

    public func prevSiblingOrToken(): ?SyntaxElement<K> {
        match (parentNode) {
            case Some(p) => p.elementAt(index - 1)
            case None => None
        }
    }

    /**
     * This node, then its sibling nodes in `direction`.
     */
    public func siblings(direction: Direction): Iterator<SyntaxNode<K>> {
        Successors<SyntaxNode<K>>(this, {n => match (direction) {
            case Next => n.nextSibling()
            case Prev => n.prevSibling()
        }})
    }

    /**
     * This node, then its siblings in `direction`, tokens included.
     */
    public func siblingsWithTokens(direction: Direction): Iterator<SyntaxElement<K>> {
        Successors<SyntaxElement<K>>(SyntaxElement.Node(this), {el => match (direction) {
            case Next => el.nextSiblingOrToken()
            case Prev => el.prevSiblingOrToken()
        }})
    }

    /**
     * This node, then its parent, and so on up to the root.
     */
    public func ancestors(): Iterator<SyntaxNode<K>> {
        Successors<SyntaxNode<K>>(this, {n => n.parentNode})
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
        Entered(preorder())
    }

    /**
     * This node and every node and token under it, in preorder.
     */
    public func descendantsWithTokens(): Iterator<SyntaxElement<K>> {
        Entered(preorderWithTokens())
    }

    /**
     * The first token under this node, skipping nodes that have none.
     */
    public func firstToken(): ?SyntaxToken<K> {
        for (i in 0..greenNode.childCount) {
            match (element(i)) {
                case SyntaxElement.Token(t) => return t
                case SyntaxElement.Node(n) => if (let Some(t) <- n.firstToken()) {
                    return t
                }
            }
        }
        None
    }

    /**
     * The last token under this node, skipping nodes that have none.
     */
    public func lastToken(): ?SyntaxToken<K> {
        var i = greenNode.childCount - 1
        while (i >= 0) {
            match (element(i)) {
                case SyntaxElement.Token(t) => return t
                case SyntaxElement.Node(n) => if (let Some(t) <- n.lastToken()) {
                    return t
                }
            }
            i--
        }
        None
    }

    /**
     * The token `offset` is inside of, or the two it is between; `NoToken` if it is outside this node.
     */
    public func tokenAtOffset(offset: Int64): TokenAtOffset<SyntaxToken<K>> {
        if (!textRange.containsInclusive(offset)) {
            return NoToken
        }
        var left = None<TokenAtOffset<SyntaxToken<K>>>
        for (i in 0..greenNode.childCount) {
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
        for (i in 0..greenNode.childCount) {
            let childRange = TextRange.at(offset + greenNode.childOffset(i), greenNode.child(i).textLen)
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
        match (parentNode) {
            case None => replacement
            case Some(p) => p.replaceWith(p.greenNode.replaceChild(index, GreenElement.Node(replacement)))
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
        refEq(this, other) || (refEq(greenNode, other.greenNode) && offset == other.offset && index == other.index)
    }

    public operator func !=(other: SyntaxNode<K>): Bool {
        !(this == other)
    }

    public func hashCode(): Int64 {
        var hasher = DefaultHasher()
        hasher.write(offset)
        hasher.write(index)
        hasher.write(greenNode.hashCode())
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
    let greenToken: GreenToken<K>
    let parentNode: SyntaxNode<K>
    let index: Int64
    let offset: Int64

    init(green: GreenToken<K>, parent: SyntaxNode<K>, index: Int64, offset: Int64) {
        this.greenToken = green
        this.parentNode = parent
        this.index = index
        this.offset = offset
    }

    public prop kind: K {
        get() {
            greenToken.kind
        }
    }

    public prop green: GreenToken<K> {
        get() {
            greenToken
        }
    }

    public prop parent: SyntaxNode<K> {
        get() {
            parentNode
        }
    }

    public prop indexInParent: Int64 {
        get() {
            index
        }
    }

    public prop textRange: TextRange {
        get() {
            TextRange(offset, offset + greenToken.textLen)
        }
    }

    public func text(): String {
        greenToken.text
    }

    public func nextSiblingOrToken(): ?SyntaxElement<K> {
        parentNode.elementAt(index + 1)
    }

    public func prevSiblingOrToken(): ?SyntaxElement<K> {
        parentNode.elementAt(index - 1)
    }

    /**
     * This token, then its siblings in `direction`, nodes included.
     */
    public func siblingsWithTokens(direction: Direction): Iterator<SyntaxElement<K>> {
        Successors<SyntaxElement<K>>(SyntaxElement.Token(this), {el => match (direction) {
            case Next => el.nextSiblingOrToken()
            case Prev => el.prevSiblingOrToken()
        }})
    }

    /**
     * The parent, then its parent, and so on up to the root.
     */
    public func ancestors(): Iterator<SyntaxNode<K>> {
        parentNode.ancestors()
    }

    /**
     * The token after this one in the text, wherever in the tree it is.
     */
    public func nextToken(): ?SyntaxToken<K> {
        var current = SyntaxElement.Token(this)
        while (true) {
            match (current.nextSiblingOrToken()) {
                case Some(SyntaxElement.Token(t)) => return t
                case Some(SyntaxElement.Node(n)) => match (n.firstToken()) {
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
     * The token before this one in the text, wherever in the tree it is.
     */
    public func prevToken(): ?SyntaxToken<K> {
        var current = SyntaxElement.Token(this)
        while (true) {
            match (current.prevSiblingOrToken()) {
                case Some(SyntaxElement.Token(t)) => return t
                case Some(SyntaxElement.Node(n)) => match (n.lastToken()) {
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
        parentNode.replaceWith(parentNode.greenNode.replaceChild(index, GreenElement.Token(replacement)))
    }

    public operator func ==(other: SyntaxToken<K>): Bool {
        refEq(this, other) || (refEq(greenToken, other.greenToken) && offset == other.offset && index == other.index &&
            parentNode == other.parentNode)
    }

    public operator func !=(other: SyntaxToken<K>): Bool {
        !(this == other)
    }

    public func hashCode(): Int64 {
        var hasher = DefaultHasher()
        hasher.write(offset)
        hasher.write(index)
        hasher.write(greenToken.hashCode())
        hasher.finish()
    }

    public func toString(): String {
        greenToken.text
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

class Entered<T> <: Iterator<T> {
    Entered(let events: Iterator<WalkEvent<T>>) {}

    public func next(): ?T {
        while (let Some(event) <- events.next()) {
            if (let Enter(v) <- event) {
                return v
            }
        }
        None
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
