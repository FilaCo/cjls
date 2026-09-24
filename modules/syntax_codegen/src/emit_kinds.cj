package syntax_codegen

import std.collection.*
import std.sort.*

func sectionTitle(category: KindCategory): String {
    match (category) {
        case Trivia => "Trivia"
        case Special => "Kinds never in a tree"
        case Punctuation => "Punctuation"
        case GluedPunctuation => "Punctuation the parser glues of joint pieces: the lexer never makes these"
        case Token => "Literals, names and other tokens"
        case Keyword => "Keywords, contextual ones included: the parser takes those for names where it can"
        case Node => "Nodes"
    }
}

/**
 * The kind enum, its methods, and the lexer's table of punctuation.
 */
func emitKinds(model: Model, header: String, packageName: String): String {
    let w = CodeWriter()
    let kinds = model.kinds
    w.line(header)
    w.blank()
    w.line("package ${packageName}")
    w.blank()
    w.line("import std.deriving.*")
    w.line("import ginkgo.Kind")
    w.blank()
    w.doc(["Every kind of token and node in a syntax tree."])
    w.line("@Derive[Equatable, Hashable]")
    w.block("public enum SyntaxKind") {
        =>
        for (i in 0..kinds.size) {
            let k = kinds[i]
            if (i == 0 || kinds[i - 1].category != k.category) {
                w.line("// ${sectionTitle(k.category)}")
            }
            for (d in k.doc) {
                w.line("/** ${d} */")
            }
            w.line("| ${k.name}")
        }
        w.blank()
        w.doc(["The kind's position in the enum, from 0."])
        w.block("public func ordinal(): Int64") {
            => w.block("match (this)") {
                => for (i in 0..kinds.size) {
                    w.line("case ${kinds[i].name} => ${i}")
                }
            }
        }
        w.blank()
        w.block("public func toString(): String") {
            => w.block("match (this)") {
                => for (k in kinds) {
                    w.line("case ${k.name} => ${quoted(k.name)}")
                }
            }
        }
        w.blank()
        predicate(w, "isTrivia", ["What the parser skips."], kinds.filter {k => k.category == Trivia})
        w.blank()
        predicate(w, "isKeyword", ["A keyword, contextual or not."], kinds.filter {k => k.category == Keyword})
        w.blank()
        predicate(w, "isContextualKeyword", ["A keyword that is a name wherever a name fits."],
            kinds.filter {k => k.category == Keyword && k.contextual})
        w.blank()
        predicate(w, "isPunctuation", ["Punctuation, the kinds the parser glues included."],
            kinds.filter {k => k.category == Punctuation || k.category == GluedPunctuation})
        w.blank()
        w.doc(["The text of a token spelled one way only."])
        w.block("public func fixedText(): ?String") {
            => w.block("match (this)") {
                =>
                for (k in kinds) {
                    if (let Some(text) <- k.text) {
                        w.line("case ${k.name} => ${quoted(text)}")
                    }
                }
                w.line("case _ => None")
            }
        }
        w.blank()
        w.doc(["The keyword, or other word, spelled `text`."])
        w.block("public static func keyword(text: String): ?SyntaxKind") {
            => w.block("match (text)") {
                =>
                for (k in kinds where k.category == Keyword || k.word) {
                    w.line("case ${quoted(k.text.getOrThrow())} => ${k.name}")
                }
                w.line("case _ => None")
            }
        }
    }
    w.blank()
    w.line("extend SyntaxKind <: Kind<SyntaxKind> {}")
    w.blank()
    w.doc(["The punctuation the lexer cuts out of the text, the longest first: it takes the first that matches."])
    w.line("let LEXED_PUNCTUATION: Array<(Array<Byte>, SyntaxKind)> = [")
    w.indented {
        =>
        let lexed = ArrayList<KindInfo>(kinds.filter {k => k.category == Punctuation})
        // stable, so kinds of one length keep their order
        sort(lexed, by: {a, b => a.text.getOrThrow().size.compare(b.text.getOrThrow().size)}, stable: true,
            descending: true)
        for (k in lexed) {
            w.line("(${quoted(k.text.getOrThrow())}.toArray(), ${k.name}),")
        }
    }
    w.line("]")
    w.toString()
}

func predicate(w: CodeWriter, name: String, doc: Array<String>, members: Array<KindInfo>): Unit {
    w.doc(doc)
    w.block("public func ${name}(): Bool") {
        => w.block("match (this)") {
            =>
            if (!members.isEmpty()) {
                w.wrapped("case ", members.map {k => k.name}, " |", " => true", leading: true)
            }
            w.line("case _ => false")
        }
    }
}
