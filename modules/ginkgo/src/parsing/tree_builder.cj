package ginkgo.parsing

import std.collection.ArrayList
import std.sort.*
import ginkgo.*

/**
 * What the tree builder needs to know about trivia, which the parser never sees.
 */
public interface TriviaRules<K> where K <: Kind<K> {
    func isTrivia(kind: K): Bool

    /**
     * How many of `trivia`, the trivia right before a node of `kind`, belong inside it rather than to its parent,
     * counted from the end: a doc comment with the declaration after it, say. By default none.
     */
    func attachedTrivia(_: K, _: Array<(K, String)>): Int64 {
        0
    }
}

public struct SyntaxError <: ToString {
    public SyntaxError(public let message: String, public let range: TextRange) {}

    public func toString(): String {
        "${range}: ${message}"
    }
}

/**
 * A parsed text: the tree, which always covers the whole text, and what was wrong with it.
 */
public class Parse<K> where K <: Kind<K> {
    public Parse(public let green: GreenNode<K>, public let errors: Array<SyntaxError>) {}

    public func syntaxNode(): SyntaxNode<K> {
        SyntaxNode.newRoot(green)
    }
}

/**
 * Builds the tree `parser` recorded over `lexed`, weaving the trivia back in: trivia before a node goes to its
 * parent, but for what `rules` attaches to it; trivia after the last token goes to the root. Whatever the parser
 * left unconsumed goes at the end of the root, in an error node, so the tree covers the text whatever the
 * grammar did.
 */
public func buildTree<K>(lexed: Lexed<K>, parser: Parser<K>, rules: TriviaRules<K>): Parse<K> where K <: Kind<K> {
    let sink = TreeSink(lexed, rules, parser.errorKind)
    let events = parser.events.toArray()
    for (i in 0..events.size) {
        match (events[i]) {
            case StartNode(kind, forward) =>
                let kinds = ArrayList<K>([kind])
                var at = i
                var next = forward
                while (next != 0) {
                    at += next
                    next = 0
                    if (let StartNode(outer, outerForward) <- events[at]) {
                        kinds.add(outer)
                        next = outerForward
                    }
                    events[at] = Tombstone
                }
                var j = kinds.size - 1
                while (j >= 0) {
                    sink.enter(kinds[j])
                    j--
                }
            case FinishNode => sink.exit()
            case AddToken(kind, n) => sink.token(kind, n)
            case AddError(message) => sink.error(message)
            case Tombstone => ()
        }
    }
    sink.finish()
}

class TreeSink<K> where K <: Kind<K> {
    let builder = GreenNodeBuilder<K>()
    let errors = ArrayList<SyntaxError>()
    var pos = 0
    var textPos = 0
    var depth = 0
    var rootFinished = false

    TreeSink(let lexed: Lexed<K>, let rules: TriviaRules<K>, let errorKind: K) {}

    func emit(i: Int64): Unit {
        builder.token(lexed.kind(i), lexed.tokenText(i))
        textPos = lexed.range(i).end
        pos = i + 1
    }

    func eatTrivia(): Unit {
        while (pos < lexed.size && rules.isTrivia(lexed.kind(pos))) {
            emit(pos)
        }
    }

    func enter(kind: K): Unit {
        if (rootFinished) {
            return
        }
        if (depth > 0) {
            var n = 0
            while (pos + n < lexed.size && rules.isTrivia(lexed.kind(pos + n))) {
                n++
            }
            let trivia = Array<(K, String)>(n) {i => (lexed.kind(pos + i), lexed.tokenText(pos + i))}
            let attached = rules.attachedTrivia(kind, trivia)
            let outside = n - (if (attached < 0) { 0 } else if (attached > n) { n } else { attached })
            for (_ in 0..outside) {
                emit(pos)
            }
        }
        builder.startNode(kind)
        depth++
    }

    func exit(): Unit {
        if (depth == 0) {
            return
        }
        if (depth == 1) {
            eatTrivia()
            if (pos < lexed.size) {
                error("unexpected input")
                builder.startNode(errorKind)
                while (pos < lexed.size) {
                    emit(pos)
                }
                builder.finishNode()
            }
            rootFinished = true
        }
        builder.finishNode()
        depth--
    }

    func token(kind: K, n: Int64): Unit {
        eatTrivia()
        if (pos >= lexed.size) {
            return
        }
        let last = if (pos + n <= lexed.size) { pos + n - 1 } else { lexed.size - 1 }
        let start = lexed.range(pos).start
        let end = lexed.range(last).end
        builder.token(kind, lexed.text[start..end])
        textPos = end
        pos = last + 1
    }

    func error(message: String): Unit {
        errors.add(SyntaxError(message, TextRange.empty(textPos)))
    }

    func finish(): Parse<K> {
        if (!rootFinished && depth == 0) {
            enter(errorKind)
        }
        while (depth > 0) {
            exit()
        }
        for (e in lexed.lexErrors()) {
            errors.add(SyntaxError(e.message, lexed.range(e.tokenIndex)))
        }
        let sorted = errors.toArray()
        sort(sorted, stable: true, by: {a: SyntaxError, b: SyntaxError => a.range.start.compare(b.range.start)})
        Parse(builder.finish(), sorted)
    }
}
