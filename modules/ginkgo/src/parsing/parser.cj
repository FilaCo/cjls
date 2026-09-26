package ginkgo.parsing

import std.collection.ArrayList
import ginkgo.*

/**
 * What a parser records, for `buildTree` to turn into a tree. A parser never builds nodes itself: it can only
 * decide what a node is once it has seen past its start (`a` becomes the left side of `a + b` at the `+`), and
 * events let it go back and wrap what it has recorded.
 */
enum Event<K> where K <: Kind<K> {
    /**
     * A node starts. A non-zero offset names the event, that far ahead, of a node that starts here too and
     * contains this one (see `CompletedMarker.precede`).
     */
    | StartNode(K, Int64)
    | FinishNode
    /**
     * A token, made of this many input tokens (more than one for a composite like `>>`).
     */
    | AddToken(K, Int64)
    | AddError(ParseError<K>)
    /**
     * A start that was abandoned, or taken over by the node it forwarded to.
     */
    | Tombstone
}

/**
 * A recursive-descent parser's view of its input: a cursor over the non-trivia tokens, and the events it records.
 * The grammar is plain functions taking one; see `Marker` for how they make nodes.
 *
 * Reading past the end gives `eof`, forever. A grammar that loops without consuming anything is caught: after
 * `STEP_LIMIT` reads at one position the parser throws instead of hanging.
 */
public class Parser<K> where K <: Kind<K> {
    static const STEP_LIMIT = 1_000_000

    /**
     * @param eof - the kind read past the end
     * @param errorKind - the node that `errAndBump` wraps an unexpected token in
     */
    public Parser(let input: Input<K>, let eof: K, let errorKind: K) {}

    var pos = 0
    var steps = 0
    let events = ArrayList<Event<K>>()

    /**
     * The kind `n` tokens ahead.
     *
     * @throws IllegalStateException - if the parser reads this position too often, stuck in a loop
     */
    public func nth(n: Int64): K {
        steps++
        if (steps > STEP_LIMIT) {
            throw IllegalStateException("The parser is stuck at token ${pos}")
        }
        let i = pos + n
        if (i < input.size) {
            input.kind(i)
        } else {
            eof
        }
    }

    public func current(): K {
        nth(0)
    }

    public func at(kind: K): Bool {
        nthAt(0, kind)
    }

    public func nthAt(n: Int64, kind: K): Bool {
        nth(n) == kind
    }

    public func atAny(kinds: Array<K>): Bool {
        nthAtAny(0, kinds)
    }

    public func nthAtAny(n: Int64, kinds: Array<K>): Bool {
        kinds.contains(nth(n))
    }

    public func atAny(kinds: TokenSet<K>): Bool {
        nthAtAny(0, kinds)
    }

    public func nthAtAny(n: Int64, kinds: TokenSet<K>): Bool {
        kinds.contains(nth(n))
    }

    /**
     * The contextual kind of the token `n` ahead, if its text gives it one (see `Lexed.toInput`).
     */
    public func nthContextual(n: Int64): ?K {
        input.contextualKind(pos + n)
    }

    public func atEof(): Bool {
        pos >= input.size
    }

    /**
     * Whether trivia counting as a newline comes before the token `n` ahead.
     */
    public func nthNewlineBefore(n: Int64): Bool {
        input.isNewlineBefore(pos + n)
    }

    /**
     * Whether trivia counting as a newline comes before the current token.
     */
    public func newlineBefore(): Bool {
        nthNewlineBefore(0)
    }

    /**
     * Whether the token `n` ahead and the one after it have nothing between them.
     */
    public func isJoint(n: Int64): Bool {
        input.isJointWithNext(pos + n)
    }

    /**
     * Whether the next tokens are `kinds`, with nothing between them: a composite token cut into pieces.
     */
    public func atComposite(kinds: Array<K>): Bool {
        for (i in 0..kinds.size) {
            if (nth(i) != kinds[i] || (i + 1 < kinds.size && !isJoint(i))) {
                return false
            }
        }
        true
    }

    /**
     * Consumes the current token, which must be `kind`.
     *
     * @throws IllegalStateException - if it is not: a bug in the grammar
     */
    public func bump(kind: K): Unit {
        if (!at(kind)) {
            throw IllegalStateException("bump(${kind}) at ${current()}")
        }
        doBump(kind, 1)
    }

    /**
     * Consumes the current token, whatever it is; nothing at the end.
     */
    public func bumpAny(): Unit {
        if (!atEof()) {
            doBump(current(), 1)
        }
    }

    /**
     * Consumes the current token as a token of `kind`: a contextual keyword used as a name, for one.
     */
    public func bumpRemap(kind: K): Unit {
        if (!atEof()) {
            doBump(kind, 1)
        }
    }

    /**
     * Consumes the next `n` tokens as one token of `kind`: `>` `>` as `>>`. Check `atComposite` first.
     */
    public func bumpComposite(kind: K, n: Int64): Unit {
        doBump(kind, n)
    }

    func doBump(kind: K, n: Int64): Unit {
        events.add(AddToken(kind, n))
        pos += n
        steps = 0
    }

    /**
     * Consumes the current token if it is `kind`.
     */
    public func eat(kind: K): Bool {
        if (at(kind)) {
            doBump(kind, 1)
            true
        } else {
            false
        }
    }

    /**
     * Consumes the current token if it is `kind`, and reports it missing otherwise, as `ParseError.Expected`: the
     * language words the message.
     */
    public func expect(kind: K): Bool {
        if (eat(kind)) {
            return true
        }
        events.add(AddError(ParseError.Expected(kind)))
        false
    }

    /**
     * Reports an error at the current position, consuming nothing.
     */
    public func error(message: String): Unit {
        events.add(AddError(ParseError.Message(message)))
    }

    /**
     * Reports an error and consumes the current token, wrapped in an error node.
     */
    public func errAndBump(message: String): Unit {
        let m = start()
        error(message)
        bumpAny()
        m.complete(this, errorKind)
    }

    /**
     * Reports an error, consuming the current token only if it is not one of `recovery`, which the grammar above
     * knows how to go on from.
     */
    public func errRecover(message: String, recovery: Array<K>): Unit {
        errRecover(message, TokenSet(recovery))
    }

    public func errRecover(message: String, recovery: TokenSet<K>): Unit {
        if (atAny(recovery) || atEof()) {
            error(message)
        } else {
            errAndBump(message)
        }
    }

    /**
     * Starts a node here: complete the marker to make it one, or abandon it.
     */
    public func start(): Marker {
        let at = events.size
        events.add(Tombstone)
        Marker(at)
    }

    /**
     * The position to `rewind` to, to try parsing a way and take it back.
     */
    public func snapshot(): ParserSnapshot {
        ParserSnapshot(pos, events.size)
    }

    /**
     * Forgets everything recorded since `snapshot`. Only markers started since may have been completed,
     * abandoned or preceded, or their events are left changed.
     */
    public func rewind(snapshot: ParserSnapshot): Unit {
        pos = snapshot.pos
        events.remove(snapshot.eventCount..events.size)
        steps = 0
    }

    /**
     * Whether an error was reported since `snapshot`.
     */
    public func hasErrorSince(snapshot: ParserSnapshot): Bool {
        for (i in snapshot.eventCount..events.size) {
            if (let AddError(_) <- events[i]) {
                return true
            }
        }
        false
    }

    /**
     * How many input tokens were consumed.
     */
    public prop position: Int64 {
        get() {
            pos
        }
    }
}

public struct ParserSnapshot {
    ParserSnapshot(let pos: Int64, let eventCount: Int64) {}
}

/**
 * A node started but not decided yet. Complete it, or abandon it: dropping it does neither and loses nothing
 * but leaves a dead event.
 */
public struct Marker {
    Marker(let eventIndex: Int64) {}

    /**
     * Makes everything consumed since the marker a node of `kind`.
     */
    public func complete<K>(p: Parser<K>, kind: K): CompletedMarker<K> where K <: Kind<K> {
        p.events[eventIndex] = StartNode(kind, 0)
        p.events.add(FinishNode)
        CompletedMarker(eventIndex, kind)
    }

    /**
     * Makes no node: what was consumed since goes to the enclosing node.
     */
    public func abandon<K>(p: Parser<K>): Unit where K <: Kind<K> {
        if (eventIndex == p.events.size - 1) {
            p.events.remove(at: eventIndex)
        }
    }
}

public struct CompletedMarker<K> where K <: Kind<K> {
    CompletedMarker(let eventIndex: Int64, public let kind: K) {}

    /**
     * Starts a node that begins where this one does and will contain it: `a` becomes the left side of `a + b`.
     */
    public func precede(p: Parser<K>): Marker {
        let m = p.start()
        if (let StartNode(k, _) <- p.events[eventIndex]) {
            p.events[eventIndex] = StartNode(k, m.eventIndex - eventIndex)
        }
        m
    }

    /**
     * Makes this node another kind.
     */
    public func changeKind(p: Parser<K>, kind: K): CompletedMarker<K> {
        if (let StartNode(_, forward) <- p.events[eventIndex]) {
            p.events[eventIndex] = StartNode(kind, forward)
        }
        CompletedMarker(eventIndex, kind)
    }
}
