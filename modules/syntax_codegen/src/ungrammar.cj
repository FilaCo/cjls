package syntax_codegen

import std.collection.*
import std.deriving.*

/**
 * A rule of an ungrammar: rust-analyzer's format for the shape of a syntax tree.
 */
enum Rule {
    | NodeRef(String)
    /** a token, by its text or its kind's name: what is between the quotes */
    | TokenRef(String)
    | Labeled(String, Rule)
    | Seq(Array<Rule>)
    | Alt(Array<Rule>)
    | Opt(Rule)
    | Rep(Rule)

    func children(): Array<Rule> {
        match (this) {
            case Labeled(_, r) => [r]
            case Seq(rs) => rs
            case Alt(rs) => rs
            case Opt(r) => [r]
            case Rep(r) => [r]
            case _ => []
        }
    }
}

struct RuleDef {
    RuleDef(let name: String, let doc: Array<String>, let rule: Rule) {}
}

struct Grammar {
    Grammar(let rules: Array<RuleDef>) {}
}

class GrammarException <: Exception {
    GrammarException(message: String) {
        super(message)
    }

    protected override func getClassName(): String {
        "GrammarException"
    }
}

@Derive[Equatable]
enum GTokenKind {
    | GIdent
    | GQuoted
    | GPunct
}

/**
 * A token of an ungrammar, with the comment lines right above it, if it starts a line.
 */
struct GToken {
    GToken(let kind: GTokenKind, let text: String, let line: Int64, let doc: Array<String>) {}

    func isPunct(c: String): Bool {
        match (kind) {
            case GPunct => text == c
            case _ => false
        }
    }
}

func lexGrammar(text: String): ArrayList<GToken> {
    let tokens = ArrayList<GToken>()
    let bytes = text.toArray()
    var pos = 0
    var line = 1
    // the comment lines of the current block, and the line the block ended on
    var comment = ArrayList<String>()
    var commentEnd = -1
    while (pos < bytes.size) {
        let b = bytes[pos]
        if (b == b'\n') {
            line++
            pos++
        } else if (b == b' ' || b == b'\t' || b == b'\r') {
            pos++
        } else if (b == b'/' && pos + 1 < bytes.size && bytes[pos + 1] == b'/') {
            let start = pos + 2
            while (pos < bytes.size && bytes[pos] != b'\n') {
                pos++
            }
            // only a comment on a line of its own documents what follows
            if (tokens.size > 0 && tokens[tokens.size - 1].line == line) {
                continue
            }
            if (commentEnd != line - 1) {
                comment = ArrayList<String>()
            }
            comment.add(String.fromUtf8(bytes[start..pos]).trimAscii())
            commentEnd = line
        } else {
            let doc = if (commentEnd == line - 1) {
                comment.toArray()
            } else {
                Array<String>()
            }
            commentEnd = -1
            comment = ArrayList<String>()
            if (isIdentByte(b)) {
                let start = pos
                while (pos < bytes.size && isIdentByte(bytes[pos])) {
                    pos++
                }
                tokens.add(GToken(GIdent, String.fromUtf8(bytes[start..pos]), line, doc))
            } else if (b == b'\'') {
                pos++
                let sb = ArrayList<Byte>()
                while (pos < bytes.size && bytes[pos] != b'\'') {
                    if (bytes[pos] == b'\\' && pos + 1 < bytes.size) {
                        pos++
                    }
                    if (bytes[pos] == b'\n') {
                        throw GrammarException("line ${line}: unterminated token")
                    }
                    sb.add(bytes[pos])
                    pos++
                }
                if (pos >= bytes.size) {
                    throw GrammarException("line ${line}: unterminated token")
                }
                pos++
                tokens.add(GToken(GQuoted, String.fromUtf8(sb.toArray()), line, doc))
            } else if (b == b'=' || b == b'|' || b == b'(' || b == b')' || b == b'?' || b == b'*' || b == b':') {
                pos++
                tokens.add(GToken(GPunct, String.fromUtf8([b]), line, doc))
            } else {
                throw GrammarException("line ${line}: unexpected character '${String.fromUtf8([b])}'")
            }
        }
    }
    tokens
}

func isIdentByte(b: Byte): Bool {
    (b >= b'a' && b <= b'z') || (b >= b'A' && b <= b'Z') || (b >= b'0' && b <= b'9') || b == b'_'
}

/**
 * Parses an ungrammar: rules `Name = ...`, each running up to the next `Name =`.
 */
func parseGrammar(text: String): Grammar {
    GrammarParser(lexGrammar(text)).grammar()
}

class GrammarParser {
    var pos = 0

    GrammarParser(let tokens: ArrayList<GToken>) {}

    func grammar(): Grammar {
        let rules = ArrayList<RuleDef>()
        let names = HashSet<String>()
        while (pos < tokens.size) {
            let t = tokens[pos]
            if (!atRuleStart()) {
                throw GrammarException("line ${t.line}: expected a rule, `Name =`")
            }
            pos += 2
            if (!names.add(t.text)) {
                throw GrammarException("line ${t.line}: a second rule for `${t.text}`")
            }
            rules.add(RuleDef(t.text, t.doc, alternatives()))
        }
        Grammar(rules.toArray())
    }

    func atRuleStart(): Bool {
        pos + 1 < tokens.size && tokens[pos].kind == GIdent && tokens[pos + 1].isPunct("=")
    }

    func atPunct(c: String): Bool {
        pos < tokens.size && tokens[pos].isPunct(c)
    }

    func line(): Int64 {
        if (pos < tokens.size) {
            tokens[pos].line
        } else {
            tokens[tokens.size - 1].line
        }
    }

    func alternatives(): Rule {
        if (atPunct("|")) {
            pos++
        }
        let alts = ArrayList<Rule>([sequence()])
        while (atPunct("|")) {
            pos++
            alts.add(sequence())
        }
        if (alts.size == 1) {
            alts[0]
        } else {
            Alt(alts.toArray())
        }
    }

    func sequence(): Rule {
        let items = ArrayList<Rule>()
        while (let Some(atom) <- postfixed()) {
            items.add(atom)
        }
        match (items.size) {
            case 0 => throw GrammarException("line ${line()}: expected a rule")
            case 1 => items[0]
            case _ => Seq(items.toArray())
        }
    }

    func postfixed(): ?Rule {
        var rule = atom() ?? return None
        while (true) {
            if (atPunct("?")) {
                rule = Opt(rule)
            } else if (atPunct("*")) {
                rule = Rep(rule)
            } else {
                break
            }
            pos++
        }
        rule
    }

    func atom(): ?Rule {
        if (pos >= tokens.size || atRuleStart()) {
            return None
        }
        let t = tokens[pos]
        match (t.kind) {
            case GIdent where pos + 1 < tokens.size && tokens[pos + 1].isPunct(":") =>
                pos += 2
                let inner = postfixed() ?? throw GrammarException("line ${t.line}: expected a rule after `${t.text}:`")
                Labeled(t.text, inner)
            case GIdent =>
                pos++
                NodeRef(t.text)
            case GQuoted =>
                pos++
                TokenRef(t.text)
            case GPunct where t.text == "(" =>
                pos++
                let inner = alternatives()
                if (!atPunct(")")) {
                    throw GrammarException("line ${line()}: expected ')'")
                }
                pos++
                inner
            case _ => None
        }
    }
}
