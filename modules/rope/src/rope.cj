package rope

import std.collection.*

/**
 * An immutable UTF-8 text, as a balanced tree of chunks: an edit costs the log of the text's size
 * rather than its size, and the rope it gives shares every chunk the edit did not touch with the
 * one it was made from, so keeping the old one costs next to nothing.
 *
 * Offsets are in bytes, and must fall between characters. Lines and columns count from zero; only
 * `\n` breaks a line (see `TextSummary`), and what a column counts is up to the `Encoding` asked
 * for.
 */
public struct Rope <: Equatable<Rope> & ToString {
    private let root: Node

    public init() {
        root = Leaf("")
    }

    public init(text: String) {
        root = rooted(chunked(text), 0)
    }

    private init(root: Node) {
        this.root = root
    }

    /**
     * In bytes.
     */
    public prop size: Int64 {
        get() {
            root.summary.bytes
        }
    }

    public prop summary: TextSummary {
        get() {
            root.summary
        }
    }

    /**
     * One more than the line breaks: an empty text, or one ending in a break, has an empty last
     * line.
     */
    public prop lineCount: Int64 {
        get() {
            root.summary.lineBreaks + 1
        }
    }

    public func isEmpty(): Bool {
        size == 0
    }

    /**
     * @throws IndexOutOfBoundsException - if `range` does not lie within the text
     * @throws IllegalArgumentException - if it starts or ends inside a character
     */
    public func replace(range: Range<Int64>, text: String): Rope {
        let (start, end) = bounds(range)
        if (start == end && text.isEmpty()) {
            return this
        }
        Rope(rooted(edit(root, start, end, text), root.height))
    }

    /**
     * @throws IndexOutOfBoundsException - if `offset` does not lie within the text
     * @throws IllegalArgumentException - if it falls inside a character
     */
    public func insert(offset: Int64, text: String): Rope {
        replace(offset..offset, text)
    }

    /**
     * @throws IndexOutOfBoundsException - if `range` does not lie within the text
     * @throws IllegalArgumentException - if it starts or ends inside a character
     */
    public func remove(range: Range<Int64>): Rope {
        replace(range, "")
    }

    /**
     * @throws IndexOutOfBoundsException - if `range` does not lie within the text
     * @throws IllegalArgumentException - if it starts or ends inside a character
     */
    public func slice(range: Range<Int64>): Rope {
        let (start, end) = bounds(range)
        remove(end..size).remove(0..start)
    }

    /**
     * The summary of the text before `offset`.
     *
     * @throws IndexOutOfBoundsException - if `offset` does not lie within the text
     * @throws IllegalArgumentException - if it falls inside a character
     */
    public func summaryBefore(offset: Int64): TextSummary {
        checkOffset(offset)
        prefixSummary(root, offset)
    }

    /**
     * The offset `line` starts at.
     *
     * @throws IndexOutOfBoundsException - if there is no such line
     */
    public func lineStart(line: Int64): Int64 {
        if (line < 0 || line >= lineCount) {
            throw IndexOutOfBoundsException("line ${line} of a text of ${lineCount}")
        }
        if (line == 0) {
            0
        } else {
            offsetAfterBreak(root, line)
        }
    }

    /**
     * The offset `line` ends at, before its line break if it has one: before the `\r` of a `\r\n`,
     * so an edit at the end of a line never splits one.
     *
     * @throws IndexOutOfBoundsException - if there is no such line
     */
    public func lineEnd(line: Int64): Int64 {
        if (line + 1 < lineCount) {
            let lineFeed = lineStart(line + 1) - 1
            if (lineFeed > 0 && byteAt(root, lineFeed - 1) == b'\r') {
                lineFeed - 1
            } else {
                lineFeed
            }
        } else {
            lineStart(line)
            size
        }
    }

    /**
     * The line `offset` is on; a line break is on the line it ends.
     *
     * @throws IndexOutOfBoundsException - if `offset` does not lie within the text
     * @throws IllegalArgumentException - if it falls inside a character
     */
    public func lineOf(offset: Int64): Int64 {
        summaryBefore(offset).lineBreaks
    }

    /**
     * The offset at `position`, whose column counts columns of `encoding`. Lenient the way LSP asks:
     * a column past the end of its line stands for the end of the line, one inside a character
     * (half a surrogate pair) for the start of that character, and a line past the last one for
     * the end of the text.
     *
     * @throws IllegalArgumentException - if the line or the column is negative
     */
    public func offsetOf(position: LineColumn, encoding: Encoding): Int64 {
        if (position.line < 0 || position.column < 0) {
            throw IllegalArgumentException("no position ${position}")
        }
        if (position.line >= lineCount) {
            return size
        }
        let start = lineStart(position.line)
        let end = lineEnd(position.line)
        let offset = match (encoding) {
            case Utf8 =>
                // a byte past the line's end is the end; one inside a character backs off to it
                var offset = min(start + position.column, end)
                while (!isCharBoundary(root, offset)) {
                    offset--
                }
                offset
            case _ =>
                let units = prefixSummary(root, start).measure(encoding) + position.column
                offsetAtUnits(root, units, encoding)
        }
        min(offset, end)
    }

    /**
     * The line and column of `offset`, the column in columns of `encoding`. The `\r` of a `\r\n`
     * is at the end of its line, so the offset after it is a column past the end.
     *
     * @throws IndexOutOfBoundsException - if `offset` does not lie within the text
     * @throws IllegalArgumentException - if it falls inside a character
     */
    public func positionOf(offset: Int64, encoding: Encoding): LineColumn {
        let before = summaryBefore(offset)
        let line = before.lineBreaks
        let start = lineStart(line)
        LineColumn(line, before.measure(encoding) - prefixSummary(root, start).measure(encoding))
    }

    /**
     * The chunks the text is kept in, in order, none empty.
     */
    public func chunks(): Iterator<String> {
        ChunkIterator(root)
    }

    public func toString(): String {
        let text = StringBuilder(max(size, 1))
        for (chunk in chunks()) {
            text.append(chunk)
        }
        text.toString()
    }

    public operator func ==(other: Rope): Bool {
        if (refEq(root, other.root)) {
            return true
        }
        if (size != other.size) {
            return false
        }
        let theirs = other.chunks()
        var chunk = ""
        var at = 0
        for (mine in chunks()) {
            for (i in 0..mine.size) {
                while (at == chunk.size) {
                    // sizes agree, so theirs run out no sooner than mine
                    chunk = theirs.next().getOrThrow()
                    at = 0
                }
                if (mine[i] != chunk[at]) {
                    return false
                }
                at++
            }
        }
        true
    }

    public operator func !=(other: Rope): Bool {
        !(this == other)
    }

    /**
     * The tree's invariants, for the tests: every leaf at height 0, and every node but the root
     * holding enough.
     */
    func checkInvariants(): Unit {
        checkNode(root, true)
    }

    private func bounds(range: Range<Int64>): (Int64, Int64) {
        if (range.step != 1) {
            throw IllegalArgumentException("a range of a text has a step of 1")
        }
        let start = if (range.hasStart) { range.start } else { 0 }
        let end = if (!range.hasEnd) {
            size
        } else if (range.isClosed) {
            range.end + 1
        } else {
            range.end
        }
        if (start < 0 || start > end || end > size) {
            throw IndexOutOfBoundsException("range ${start}..${end} of a text of ${size} bytes")
        }
        checkBoundary(start)
        checkBoundary(end)
        (start, end)
    }

    private func checkOffset(offset: Int64): Unit {
        if (offset < 0 || offset > size) {
            throw IndexOutOfBoundsException("offset ${offset} of a text of ${size} bytes")
        }
        checkBoundary(offset)
    }

    private func checkBoundary(offset: Int64): Unit {
        if (!isCharBoundary(root, offset)) {
            throw IllegalArgumentException("offset ${offset} is inside a character")
        }
    }
}

private func checkNode(node: Node, isRoot: Bool): Unit {
    match (node) {
        case leaf: Leaf =>
            if (leaf.height != 0) {
                throw IllegalStateException("a leaf at height ${leaf.height}")
            }
            if (leaf.text.size > MAX_CHUNK || !isRoot && leaf.text.size < MIN_CHUNK) {
                throw IllegalStateException("a leaf of ${leaf.text.size} bytes")
            }
        case branch: Branch =>
            let count = branch.children.size
            if (count > MAX_CHILDREN || !isRoot && count < MIN_CHILDREN || isRoot && count < 2) {
                throw IllegalStateException("a branch of ${count} children")
            }
            for (child in branch.children) {
                if (child.height != branch.height - 1) {
                    throw IllegalStateException("a child at height ${child.height} of a branch at ${branch.height}")
                }
                checkNode(child, false)
            }
    }
}
