package ginkgo.parsing

import std.collection.ArrayList
import ginkgo.*

/**
 * A text cut into tokens, trivia included, as a lexer makes them: the tokens cover the text exactly, in order.
 */
public class Lexed<K> where K <: Kind<K> {
    let kinds = ArrayList<K>()
    let starts = ArrayList<Int64>()
    let errors = ArrayList<LexError>()
    var end = 0

    public Lexed(public let text: String) {}

    /**
     * Appends a token of `len` bytes, right after the previous one.
     *
     * @throws IllegalArgumentException - if it would run past the end of the text, or is empty
     */
    public func push(kind: K, len: Int64): Unit {
        if (len <= 0 || end + len > text.size) {
            throw IllegalArgumentException("A token of ${len} bytes at ${end} does not fit a text of ${text.size}")
        }
        kinds.add(kind)
        starts.add(end)
        end += len
    }

    /**
     * Reports something wrong with the token pushed last.
     */
    public func error(message: String): Unit {
        errors.add(LexError(kinds.size - 1, message))
    }

    /**
     * How many tokens there are.
     */
    public prop size: Int64 {
        get() {
            kinds.size
        }
    }

    /**
     * Where the tokens pushed so far end.
     */
    public prop covered: Int64 {
        get() {
            end
        }
    }

    public func kind(i: Int64): K {
        kinds[i]
    }

    public func range(i: Int64): TextRange {
        let tokenEnd = if (i + 1 < starts.size) { starts[i + 1] } else { end }
        TextRange(starts[i], tokenEnd)
    }

    public func tokenText(i: Int64): String {
        let r = range(i)
        text[r.start..r.end]
    }

    public func lexErrors(): Array<LexError> {
        errors.toArray()
    }

    /**
     * What the parser sees: the tokens but trivia, each marked with whether trivia comes before it, and whether
     * trivia counting as a newline does. `contextual` gives a token a second kind by its text, for the grammar
     * to ask about: a name that is a keyword in some places only.
     */
    public func toInput(isTrivia: (K) -> Bool, isNewline: (K) -> Bool,
        contextual!: (K, String) -> ?K = {_, _ => None}): Input<K> {
        let input = Input<K>()
        var afterTrivia = false
        var afterNewline = false
        for (i in 0..kinds.size) {
            let kind = kinds[i]
            if (isTrivia(kind)) {
                afterTrivia = true
                afterNewline = afterNewline || isNewline(kind)
                continue
            }
            if (input.size > 0 && !afterTrivia) {
                input.markJointWithNext()
            }
            input.push(kind, afterNewline)
            if (let Some(ctx) <- contextual(kind, tokenText(i))) {
                input.setContextual(ctx)
            }
            afterTrivia = false
            afterNewline = false
        }
        input
    }
}

public struct LexError {
    public LexError(public let tokenIndex: Int64, public let message: String) {}
}

/**
 * The tokens a parser reads, trivia left out, as kinds and two facts about their surroundings: whether there
 * was a newline before one, and whether one is joint with the next (nothing between them), which is how a parser
 * tells `>>` from `> >` when its lexer cuts `>` alone.
 */
public class Input<K> where K <: Kind<K> {
    let kinds = ArrayList<K>()
    let newlineBefore = ArrayList<Bool>()
    let jointWithNext = ArrayList<Bool>()
    let contextualKinds = ArrayList<?K>()

    public init() {}

    public func push(kind: K, afterNewline: Bool): Unit {
        kinds.add(kind)
        newlineBefore.add(afterNewline)
        jointWithNext.add(false)
        contextualKinds.add(None)
    }

    /**
     * Gives the token pushed last a contextual kind.
     */
    public func setContextual(kind: K): Unit {
        contextualKinds[contextualKinds.size - 1] = kind
    }

    public func contextualKind(i: Int64): ?K {
        if (i < contextualKinds.size) {
            contextualKinds[i]
        } else {
            None
        }
    }

    /**
     * Marks the token pushed last as joint with the one pushed next.
     */
    public func markJointWithNext(): Unit {
        jointWithNext[jointWithNext.size - 1] = true
    }

    public prop size: Int64 {
        get() {
            kinds.size
        }
    }

    public func kind(i: Int64): K {
        kinds[i]
    }

    public func isNewlineBefore(i: Int64): Bool {
        i < newlineBefore.size && newlineBefore[i]
    }

    public func isJointWithNext(i: Int64): Bool {
        i < jointWithNext.size && jointWithNext[i]
    }
}
