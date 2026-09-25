package cjsyntax

import std.collection.ArrayList
import std.unicode.*
import ginkgo.parsing.Lexed

/**
 * Cuts Cangjie source into tokens, trivia included, never failing: what it does not know becomes an
 * `ErrorToken`, and what is wrong is reported on the token.
 *
 * It follows the compiler's lexer (`cangjie_compiler/src/Lex`) with two differences a lossless tree needs. A
 * string is not one token but its pieces — `StringStart`, `StringContent`, `InterpolationStart`, the tokens of
 * the interpolation, `InterpolationEnd`, `StringEnd` — so the expressions inside get parsed like any other. And
 * `>` and `?` are always cut alone, as the compiler does in its parser's mode: `>>`, `>=`, `>>=` and `??` are the
 * parser's to glue, as only it can tell `a >> b` from the end of `Array<Array<T>>`.
 */
public func tokenize(text: String): Lexed<SyntaxKind> {
    Lexer(text).run()
}

/**
 * The lexer's context: code, whose `{`s it counts to find the `}` ending an interpolation, or a string.
 */
class Frame {
    var braceDepth = 0

    Frame(let inString: Bool, let quoteChar: Byte, let multiline: Bool) {}
}

class Lexer {
    let bytes: Array<Byte>
    let lexed: Lexed<SyntaxKind>
    let frames = ArrayList<Frame>()
    var pos = 0

    Lexer(text: String) {
        bytes = text.toArray()
        lexed = Lexed<SyntaxKind>(text)
        frames.add(Frame(false, 0, false))
    }

    func run(): Lexed<SyntaxKind> {
        while (pos < bytes.size) {
            let frame = frames[frames.size - 1]
            if (frame.inString) {
                stringPiece(frame)
            } else {
                codeToken(frame)
            }
        }
        if (frames.size > 1 && lexed.size > 0) {
            lexed.error(if (frames[frames.size - 1].inString) {
                "unterminated string"
            } else {
                "unterminated interpolation"
            })
        }
        lexed
    }

    func peek(n: Int64): Byte {
        if (pos + n < bytes.size) {
            bytes[pos + n]
        } else {
            0
        }
    }

    func emit(kind: SyntaxKind, start: Int64): Unit {
        lexed.push(kind, pos - start)
    }

    func emitError(kind: SyntaxKind, start: Int64, message: String): Unit {
        emit(kind, start)
        lexed.error(message)
    }

    func popFrame(): Unit {
        frames.remove(at: frames.size - 1)
    }

    func atLineBreak(): Bool {
        let b = peek(0)
        b == b'\n' || (b == b'\r' && peek(1) == b'\n')
    }

    func atClosingQuote(frame: Frame): Bool {
        peek(0) == frame.quoteChar && (!frame.multiline || (peek(1) == frame.quoteChar && peek(2) == frame.quoteChar))
    }

    func stringPiece(frame: Frame): Unit {
        let start = pos
        if (atClosingQuote(frame)) {
            pos += if (frame.multiline) { 3 } else { 1 }
            emit(StringEnd, start)
            popFrame()
            return
        }
        if (peek(0) == b'$' && peek(1) == b'{') {
            pos += 2
            emit(InterpolationStart, start)
            frames.add(Frame(false, 0, false))
            return
        }
        if (!frame.multiline && atLineBreak()) {
            lexed.error("unterminated string")
            popFrame()
            return
        }
        var problem = None<String>
        while (pos < bytes.size) {
            if (atClosingQuote(frame) || (peek(0) == b'$' && peek(1) == b'{') || (!frame.multiline && atLineBreak())) {
                break
            }
            if (peek(0) == b'\\') {
                if (let Some(message) <- escapeSequence()) {
                    problem = problem ?? message
                }
                continue
            }
            pos++
        }
        emit(StringContent, start)
        if (let Some(message) <- problem) {
            lexed.error(message)
        }
    }

    /**
     * Consumes an escape, at its `\`: what is wrong with it, if anything.
     */
    func escapeSequence(): ?String {
        pos++
        let c = peek(0)
        match (c) {
            case b't' | b'b' | b'r' | b'n' | b'f' | b'v' | b'0' | b'\'' | b'"' | b'\\' | b'$' =>
                pos++
                None
            case b'u' =>
                pos++
                if (peek(0) != b'{') {
                    return "expected '{' in a unicode escape"
                }
                pos++
                var digits = 0
                while (isHexDigit(peek(0))) {
                    pos++
                    digits++
                }
                if (digits == 0 || digits > 8 || peek(0) != b'}') {
                    return "expected '}' or a hexadecimal digit in a unicode escape"
                }
                pos++
                None
            case _ where pos >= bytes.size || atLineBreak() => "unterminated escape"
            case _ =>
                pos += utf8Len(c)
                "unrecognized escape"
        }
    }

    func codeToken(frame: Frame): Unit {
        let start = pos
        let b = bytes[pos]
        match (b) {
            case b' ' | b'\t' | b'\f' =>
                while (peek(0) == b' ' || peek(0) == b'\t' || peek(0) == b'\f') {
                    pos++
                }
                emit(Whitespace, start)
            case b'\n' | b'\r' where atLineBreak() =>
                while (atLineBreak()) {
                    pos += if (peek(0) == b'\r') { 2 } else { 1 }
                }
                emit(Newline, start)
            case b'/' where peek(1) == b'/' =>
                while (pos < bytes.size && !atLineBreak()) {
                    pos++
                }
                emit(LineComment, start)
            case b'/' where peek(1) == b'*' => blockComment(start)
            case b'"' | b'\'' => stringStart(start, b)
            case b'J' where peek(1) == b'"' =>
                pos += 2
                emit(StringStart, start)
                frames.add(Frame(true, b'"', false))
            case b'r' where peek(1) == b'\'' || peek(1) == b'"' => runeLiteral(start, RuneLit)
            case b'b' where peek(1) == b'\'' => runeLiteral(start, ByteLit)
            case b'#' => rawStringOrHash(start)
            case b'`' => emitIdentifier(Ident, start, backquotedIdentifier())
            case b'$' where isIdentStart(1) || peek(1) == b'`' =>
                pos++
                if (peek(0) == b'`') {
                    emitIdentifier(DollarIdent, start, backquotedIdentifier())
                } else {
                    identifierRest()
                    if (SyntaxKind.keyword(String.fromUtf8(bytes[start + 1..pos])).isSome()) {
                        emitError(DollarIdent, start, "expected an identifier after '$', found a keyword")
                    } else {
                        emit(DollarIdent, start)
                    }
                }
            case _ where isAsciiDigit(b) || (b == b'.' && isAsciiDigit(peek(1))) => number(start)
            case _ where isIdentStart(0) =>
                identifierRest()
                let text = String.fromUtf8(bytes[start..pos])
                emit(SyntaxKind.keyword(text) ?? Ident, start)
            case b'{' =>
                frame.braceDepth++
                pos++
                emit(LBrace, start)
            case b'}' =>
                pos++
                if (frame.braceDepth == 0 && frames.size > 1) {
                    emit(InterpolationEnd, start)
                    popFrame()
                } else {
                    if (frame.braceDepth > 0) {
                        frame.braceDepth--
                    }
                    emit(RBrace, start)
                }
            case _ => punctuationOrError(start)
        }
    }

    func punctuationOrError(start: Int64): Unit {
        for ((text, kind) in LEXED_PUNCTUATION) {
            if (matches(text)) {
                pos += text.size
                emit(kind, start)
                return
            }
        }
        pos += utf8Len(bytes[pos])
        emitError(ErrorToken, start, "unknown character")
    }

    func matches(text: Array<Byte>): Bool {
        pos + text.size <= bytes.size && bytes[pos..pos + text.size] == text
    }

    func blockComment(start: Int64): Unit {
        pos += 2
        var depth = 1
        while (pos < bytes.size && depth > 0) {
            if (peek(0) == b'*' && peek(1) == b'/') {
                depth--
                pos += 2
            } else if (peek(0) == b'/' && peek(1) == b'*') {
                depth++
                pos += 2
            } else {
                pos++
            }
        }
        if (depth > 0) {
            emitError(BlockComment, start, "unterminated block comment")
        } else {
            emit(BlockComment, start)
        }
    }

    func stringStart(start: Int64, quoteChar: Byte): Unit {
        let multiline = peek(1) == quoteChar && peek(2) == quoteChar
        pos += if (multiline) { 3 } else { 1 }
        emit(StringStart, start)
        frames.add(Frame(true, quoteChar, multiline))
    }

    /**
     * `r'a'`, `r"\n"`, `b'\u{7F}'`.
     */
    func runeLiteral(start: Int64, kind: SyntaxKind): Unit {
        let quoteChar = peek(1)
        pos += 2
        if (peek(0) == quoteChar || atLineBreak() || pos >= bytes.size) {
            if (peek(0) == quoteChar) {
                pos++
            }
            emitError(kind, start, "empty character literal")
            return
        }
        var problem = None<String>
        if (peek(0) == b'\\') {
            problem = escapeSequence()
        } else {
            pos += utf8Len(bytes[pos])
        }
        if (peek(0) == quoteChar) {
            pos++
            match (problem) {
                case Some(message) => emitError(kind, start, message)
                case None => emit(kind, start)
            }
            return
        }
        while (pos < bytes.size && peek(0) != quoteChar && !atLineBreak()) {
            pos++
        }
        if (peek(0) == quoteChar) {
            pos++
        }
        emitError(kind, start, "a character literal holds one character")
    }

    /**
     * `#"..."#`, `##'...'##`; a lone `#` otherwise, as a `quote(...)` may hold one.
     */
    func rawStringOrHash(start: Int64): Unit {
        var hashes = 0
        while (peek(hashes) == b'#') {
            hashes++
        }
        let quoteChar = peek(hashes)
        if (quoteChar != b'"' && quoteChar != b'\'') {
            pos++
            emit(Hash, start)
            return
        }
        pos += hashes + 1
        while (pos < bytes.size) {
            if (peek(0) == quoteChar) {
                var n = 0
                while (n < hashes && peek(1 + n) == b'#') {
                    n++
                }
                if (n == hashes) {
                    pos += 1 + hashes
                    emit(RawStringLit, start)
                    return
                }
            }
            pos++
        }
        emitError(RawStringLit, start, "unterminated raw string")
    }

    /**
     * Whether it is well formed: closed, on its line, and not empty.
     */
    func backquotedIdentifier(): Bool {
        let open = pos
        pos++
        while (pos < bytes.size && peek(0) != b'`' && !atLineBreak()) {
            pos++
        }
        let closed = peek(0) == b'`'
        if (closed) {
            pos++
        }
        closed && isName(String.fromUtf8(bytes[open + 1..pos - 1]))
    }

    func emitIdentifier(kind: SyntaxKind, start: Int64, wellFormed: Bool): Unit {
        if (wellFormed) {
            emit(kind, start)
        } else {
            emitError(kind, start, "a backquoted identifier must be closed and hold a name")
        }
    }

    func isIdentStart(n: Int64): Bool {
        let b = peek(n)
        if (b < 0x80) {
            return isAsciiIdentStart(b)
        }
        let (r, _) = Rune.fromUtf8(bytes, pos + n)
        isIdentLike(r)
    }

    func identifierRest(): Unit {
        pos += utf8Len(bytes[pos])
        while (pos < bytes.size) {
            let b = bytes[pos]
            if (b < 0x80) {
                if (isAsciiIdentStart(b) || isAsciiDigit(b)) {
                    pos++
                    continue
                }
                return
            }
            let (r, size) = Rune.fromUtf8(bytes, pos)
            if (!isIdentLike(r)) {
                return
            }
            pos += size
        }
    }

    /**
     * `0x1F`, `1_000u16`, `3.14`, `.5`, `1e-3f32`, `0x1p4`. What follows a number and could continue a name is
     * taken as a wrong suffix rather than left to start one, as the compiler does.
     */
    func number(start: Int64): Unit {
        var base = 10
        if (peek(0) == b'0') {
            match (peek(1)) {
                case b'x' | b'X' => base = 16
                case b'o' | b'O' => base = 8
                case b'b' | b'B' => base = 2
                case _ => ()
            }
            if (base != 10) {
                pos += 2
            }
        }
        var isFloat = false
        digits(base)
        // As in the compiler, only a decimal digit after the dot makes a fraction, in hex too: `0x1.f` is `0x1`, `.f`.
        let fraction = peek(0) == b'.' && (base == 10 || base == 16) && isAsciiDigit(peek(1))
        if (fraction) {
            pos++
            digits(base)
            isFloat = true
        }
        var exponent = false
        let e = peek(0)
        if ((base == 10 && (e == b'e' || e == b'E')) || (base == 16 && (e == b'p' || e == b'P'))) {
            let sign = if (peek(1) == b'-' || peek(1) == b'+') { 1 } else { 0 }
            if (isAsciiDigit(peek(1 + sign))) {
                pos += 1 + sign
                digits(10)
                isFloat = true
                exponent = true
            }
        }
        if (base == 16 && fraction && !exponent) {
            emitError(FloatLit, start, "a hexadecimal float needs an exponent part")
            return
        }
        var valid = true
        let s = peek(0)
        if ((s == b'i' || s == b'u') && !isFloat && isAsciiDigit(peek(1))) {
            pos++
            valid = suffix(["8", "16", "32", "64"])
        } else if (s == b'f' && base == 10 && isAsciiDigit(peek(1))) {
            pos++
            valid = suffix(["16", "32", "64"])
            isFloat = true
        }
        if (pos < bytes.size && isIdentStart(0)) {
            identifierRest()
            valid = false
        }
        let kind = if (isFloat) { FloatLit } else { IntLit }
        if (valid) {
            emit(kind, start)
        } else {
            emitError(kind, start, "invalid suffix on a number")
        }
    }

    func digits(base: Int64): Unit {
        while (pos < bytes.size) {
            let b = bytes[pos]
            if (b == b'_' || isAsciiDigit(b) || (base == 16 && isHexDigit(b))) {
                pos++
            } else {
                return
            }
        }
    }

    func suffix(allowed: Array<String>): Bool {
        let start = pos
        while (isAsciiDigit(peek(0))) {
            pos++
        }
        let text = String.fromUtf8(bytes[start..pos])
        allowed.any {a => a == text}
    }
}

/**
 * Whether `text` is a name, keywords included, as a backquoted identifier must hold: not empty, not `_`, not
 * starting with a digit.
 */
func isName(text: String): Bool {
    if (text.isEmpty() || text == "_") {
        return false
    }
    var first = true
    for (r in text.runes()) {
        let ok = if (UInt32(r) < 0x80) {
            let b = UInt8(UInt32(r))
            isAsciiIdentStart(b) || (!first && isAsciiDigit(b))
        } else {
            isIdentLike(r)
        }
        if (!ok) {
            return false
        }
        first = false
    }
    true
}

func isAsciiIdentStart(b: Byte): Bool {
    (b >= b'a' && b <= b'z') || (b >= b'A' && b <= b'Z') || b == b'_'
}

func isAsciiDigit(b: Byte): Bool {
    b >= b'0' && b <= b'9'
}

func isHexDigit(b: Byte): Bool {
    isAsciiDigit(b) || (b >= b'a' && b <= b'f') || (b >= b'A' && b <= b'F')
}

/**
 * A non-ASCII character that may be part of a name. Deliberately wider than Unicode's XID classes, which Cangjie
 * uses: `std.unicode` has no general categories, and letters newer than its tables, combining marks and the like
 * must not break a name apart. So anything but white space, punctuation and symbols is taken.
 */
func isIdentLike(r: Rune): Bool {
    if (r.isLetter() || r.isNumber()) {
        return true
    }
    if (r.isWhiteSpace()) {
        return false
    }
    let c = UInt32(r)
    let excluded = (c >= 0x80 && c <= 0xBF && c != 0xAA && c != 0xB5 && c != 0xB7 && c != 0xBA) ||
        c == 0xD7 || c == 0xF7 || (c >= 0x2000 && c <= 0x206F && c != 0x200C && c != 0x200D && c != 0x203F &&
        c != 0x2040 && c != 0x2054) || (c >= 0x2190 && c <= 0x2BFF) || (c >= 0x3000 && c <= 0x303F) ||
        (c >= 0xFE10 && c <= 0xFE1F) || (c >= 0xFE30 && c <= 0xFE6F) || (c >= 0xFF01 && c <= 0xFF0F) ||
        (c >= 0xFF1A && c <= 0xFF20) || (c >= 0xFF3B && c <= 0xFF40) || (c >= 0xFF5B && c <= 0xFF65) ||
        (c >= 0x1F000 && c <= 0x1FAFF)
    !excluded
}

func utf8Len(b: Byte): Int64 {
    if (b < 0x80) {
        1
    } else if (b >= 0xF0) {
        4
    } else if (b >= 0xE0) {
        3
    } else if (b >= 0xC0) {
        2
    } else {
        1
    }
}
