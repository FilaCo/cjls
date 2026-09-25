package rope

import std.collection.*

/**
 * A leaf holds at most this many bytes, give or take a character cut short.
 */
const MAX_CHUNK: Int64 = 1024

/**
 * A leaf holding less is merged into a neighbour whenever an edit passes by.
 */
const MIN_CHUNK: Int64 = 256

const MAX_CHILDREN: Int64 = 8

const MIN_CHILDREN: Int64 = MAX_CHILDREN / 2

/**
 * A node of the B-tree a rope is: leaves hold the text, cut on character boundaries, and every
 * node knows the summary of what is under it, which is what lets a lookup by any measure go
 * straight down. Nodes never change, so ropes share every node an edit did not pass through.
 *
 * Every leaf is at height 0, so the children of a branch are all of one height. Every node but the
 * root holds at least `MIN_CHILDREN` children, or `MIN_CHUNK` bytes.
 */
sealed abstract class Node {
    Node(let summary: TextSummary, let height: Int64) {}
}

class Leaf <: Node {
    Leaf(let text: String) {
        super(TextSummary.of(text), 0)
    }
}

class Branch <: Node {
    Branch(height: Int64, let children: Array<Node>) {
        super(summaryOf(children), height)
    }
}

private func summaryOf(children: Array<Node>): TextSummary {
    var summary = TextSummary.EMPTY
    for (child in children) {
        summary = summary + child.summary
    }
    summary
}

/**
 * `node` with `start..end` replaced by `text`: the nodes of its height that stand for it now, none
 * if nothing is left of it. `start` and `end` are character boundaries.
 */
func edit(node: Node, start: Int64, end: Int64, text: String): ArrayList<Node> {
    match (node) {
        case leaf: Leaf =>
            let old = leaf.text
            chunked(old[..start] + text + old[end..])
        case branch: Branch => editBranch(branch, start, end, text)
    }
}

/**
 * The text goes into the first child the range touches, and at a boundary between two children,
 * into the one before it: typing at the end of a chunk appends to it.
 */
private func editBranch(branch: Branch, start: Int64, end: Int64, text: String): ArrayList<Node> {
    let children = branch.children
    var first = -1
    var firstOffset = 0
    var last = -1
    var lastOffset = 0
    var offset = 0
    for (i in 0..children.size) {
        let childEnd = offset + children[i].summary.bytes
        if (first < 0 && start <= childEnd) {
            first = i
            firstOffset = offset
        }
        if (end <= childEnd) {
            last = i
            lastOffset = offset
            break
        }
        offset = childEnd
    }

    let result = ArrayList<Node>(children[..first])
    if (first == last) {
        result.add(all: edit(children[first], start - firstOffset, end - firstOffset, text))
    } else {
        let firstChild = children[first]
        result.add(all: edit(firstChild, start - firstOffset, firstChild.summary.bytes, text))
        result.add(all: edit(children[last], 0, end - lastOffset, ""))
    }
    result.add(all: children[last + 1..])
    grouped(normalized(result), branch.height)
}

/**
 * `text` in leaves, as few as `MAX_CHUNK` allows and all about the same size; none for no text.
 */
func chunked(text: String): ArrayList<Node> {
    let leaves = ArrayList<Node>()
    if (text.isEmpty()) {
        return leaves
    }
    // a cut backs off to the character's start, by up to three bytes
    let pieces = (text.size + MAX_CHUNK - 4) / (MAX_CHUNK - 3)
    var from = 0
    for (piece in 1..pieces) {
        var cut = text.size * piece / pieces
        while (isContinuation(text[cut])) {
            cut--
        }
        leaves.add(Leaf(text[from..cut]))
        from = cut
    }
    leaves.add(Leaf(text[from..]))
    leaves
}

/**
 * `nodes`, siblings, with every one holding too little merged into the one before it.
 */
func normalized(nodes: ArrayList<Node>): ArrayList<Node> {
    let result = ArrayList<Node>()
    for (node in nodes) {
        if (result.isEmpty()) {
            result.add(node)
            continue
        }
        let previous = result[result.size - 1]
        if (isUnderfull(previous) || isUnderfull(node)) {
            result.remove(at: result.size - 1)
            result.add(all: merged(previous, node))
        } else {
            result.add(node)
        }
    }
    result
}

private func isUnderfull(node: Node): Bool {
    match (node) {
        case leaf: Leaf => leaf.summary.bytes < MIN_CHUNK
        case branch: Branch => branch.children.size < MIN_CHILDREN
    }
}

/**
 * Two siblings as one node, or as two of about the same size if one would hold too much.
 */
private func merged(left: Node, right: Node): ArrayList<Node> {
    match ((left, right)) {
        case (l: Leaf, r: Leaf) => chunked(l.text + r.text)
        case (l: Branch, r: Branch) =>
            let children = ArrayList<Node>(l.children)
            children.add(all: r.children)
            // a lone child can be as underfull as its parent: the seam is normalized all the way down
            grouped(normalized(children), l.height)
        case _ => throw IllegalStateException("siblings are of one height")
    }
}

/**
 * `nodes` as the children of branches at `height`, as few as `MAX_CHILDREN` allows and all about
 * the same size.
 */
func grouped(nodes: ArrayList<Node>, height: Int64): ArrayList<Node> {
    let all = nodes.toArray()
    let groups = (all.size + MAX_CHILDREN - 1) / MAX_CHILDREN
    let branches = ArrayList<Node>()
    for (group in 0..groups) {
        branches.add(Branch(height, all[all.size * group / groups..all.size * (group + 1) / groups]))
    }
    branches
}

/**
 * The root standing for `nodes`, siblings at `height`: branches on top of them until one is left,
 * and no branch of a single child above it.
 */
func rooted(nodes: ArrayList<Node>, height: Int64): Node {
    if (nodes.isEmpty()) {
        return Leaf("")
    }
    var level = nodes
    var levelHeight = height
    while (level.size > 1) {
        levelHeight++
        level = grouped(level, levelHeight)
    }
    var root = level[0]
    while (true) {
        match (root) {
            case branch: Branch where branch.children.size == 1 => root = branch.children[0]
            case _ => break
        }
    }
    root
}

/**
 * The summary of the first `offset` bytes under `node`.
 */
func prefixSummary(node: Node, offset: Int64): TextSummary {
    match (node) {
        case leaf: Leaf => summarize(leaf.text, 0, offset)
        case branch: Branch =>
            var summary = TextSummary.EMPTY
            var remaining = offset
            for (child in branch.children) {
                if (remaining < child.summary.bytes) {
                    return summary + prefixSummary(child, remaining)
                }
                summary = summary + child.summary
                remaining -= child.summary.bytes
            }
            summary
    }
}

/**
 * The offset right after the `n`th line break under `node`, from 1.
 */
func offsetAfterBreak(node: Node, n: Int64): Int64 {
    match (node) {
        case leaf: Leaf =>
            let text = leaf.text
            var seen = 0
            for (i in 0..text.size where text[i] == b'\n') {
                seen++
                if (seen == n) {
                    return i + 1
                }
            }
            throw IllegalStateException("fewer than ${n} line breaks in a leaf")
        case branch: Branch =>
            var offset = 0
            var remaining = n
            for (child in branch.children) {
                if (remaining <= child.summary.lineBreaks) {
                    return offset + offsetAfterBreak(child, remaining)
                }
                remaining -= child.summary.lineBreaks
                offset += child.summary.bytes
            }
            throw IllegalStateException("fewer than ${n} line breaks in a branch")
    }
}

/**
 * The offset of the last character boundary under `node` at most `units` columns of `encoding`
 * in: a column inside a character, as the second half of a surrogate pair is, rounds down.
 */
func offsetAtUnits(node: Node, units: Int64, encoding: Encoding): Int64 {
    match (node) {
        case leaf: Leaf =>
            let text = leaf.text
            var counted = 0
            var i = 0
            while (i < text.size) {
                let lead = text[i]
                let width = charUnits(lead, encoding)
                if (counted + width > units) {
                    return i
                }
                counted += width
                i += charWidth(lead)
            }
            i
        case branch: Branch =>
            var offset = 0
            var remaining = units
            for (child in branch.children) {
                let measured = child.summary.measure(encoding)
                if (remaining < measured) {
                    return offset + offsetAtUnits(child, remaining, encoding)
                }
                remaining -= measured
                offset += child.summary.bytes
            }
            offset
    }
}

/**
 * The byte at `offset` under `node`, which holds more than `offset` bytes.
 */
func byteAt(node: Node, offset: Int64): Byte {
    match (node) {
        case leaf: Leaf => leaf.text[offset]
        case branch: Branch =>
            var remaining = offset
            for (child in branch.children) {
                if (remaining < child.summary.bytes) {
                    return byteAt(child, remaining)
                }
                remaining -= child.summary.bytes
            }
            throw IndexOutOfBoundsException("offset ${offset} of a node of ${branch.summary.bytes} bytes")
    }
}

/**
 * Whether `offset` under `node` falls between two characters.
 */
func isCharBoundary(node: Node, offset: Int64): Bool {
    match (node) {
        case leaf: Leaf => offset == leaf.text.size || !isContinuation(leaf.text[offset])
        case branch: Branch =>
            var remaining = offset
            for (child in branch.children) {
                if (remaining < child.summary.bytes) {
                    return isCharBoundary(child, remaining)
                }
                remaining -= child.summary.bytes
            }
            true
    }
}

/**
 * The leaves of a tree, left to right, empty ones skipped.
 */
class ChunkIterator <: Iterator<String> {
    private let pending = ArrayList<Node>()

    ChunkIterator(root: Node) {
        pending.add(root)
    }

    public func next(): ?String {
        while (!pending.isEmpty()) {
            let node = pending[pending.size - 1]
            pending.remove(at: pending.size - 1)
            match (node) {
                case leaf: Leaf where !leaf.text.isEmpty() => return leaf.text
                case branch: Branch =>
                    for (i in branch.children.size - 1..=0 : -1) {
                        pending.add(branch.children[i])
                    }
                case _ => ()
            }
        }
        None
    }
}
