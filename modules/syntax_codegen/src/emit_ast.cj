package syntax_codegen

import std.collection.*

let NODE_TYPE = "SyntaxNode<SyntaxKind>"
let TOKEN_TYPE = "SyntaxToken<SyntaxKind>"

/**
 * The typed views of the grammar: a struct for every node, an enum for every rule listing nodes.
 */
func emitAst(model: Model, header: String, packageName: String): String {
    let views = CodeWriter()
    // the token sets the accessors use, by name: a global must come before what uses it in its file
    let sets = ArrayList<(String, Array<String>)>()
    for (r in model.grammar.rules) {
        views.blank()
        match (model.enumOf(r.name)) {
            case Some(e) => emitEnum(views, model, e)
            case None => emitNode(views, nodeIr(model, r.name), sets)
        }
    }
    let w = CodeWriter()
    w.line(header)
    w.blank()
    w.line("package ${packageName}")
    w.blank()
    w.line("import std.deriving.*")
    w.line("import ginkgo.*")
    w.line("import cjsyntax.SyntaxKind")
    for ((name, kinds) in sets) {
        w.blank()
        w.wrapped("let ${name} = TokenSet<SyntaxKind>([", kinds.map {k => "SyntaxKind.${k}"}, ",", "])")
    }
    "${w}${views}"
}

func nodeIr(model: Model, name: String): NodeIr {
    for (n in model.nodes where n.name == name) {
        return n
    }
    throw IllegalStateException("no node `${name}`")
}

func emitNode(w: CodeWriter, n: NodeIr, sets: ArrayList<(String, Array<String>)>): Unit {
    let doc = ArrayList<String>(n.doc)
    if (!n.handWritten.isEmpty()) {
        if (!doc.isEmpty()) {
            doc.add("")
        }
        let names = n.handWritten.map {f => "`${f}`"}
        doc.add("Written by hand, as the grammar cannot tell them by position: ${String.join(names, delimiter: ", ")}.")
    }
    w.doc(doc.toArray())
    w.line("@Derive[Equatable, Hashable]")
    w.block("public struct ${n.name} <: AstNode<SyntaxKind, ${n.name}> & ToString") {
        =>
        w.line("${n.name}(let node: ${NODE_TYPE}) {}")
        w.blank()
        w.block("public static func canCast(kind: SyntaxKind): Bool") {=> w.line("kind == SyntaxKind.${n.name}")}
        w.blank()
        w.block("public static func cast(node: ${NODE_TYPE}): ?${n.name}") {
            =>
            w.line("if (canCast(node.kind)) {")
            w.indented {=> w.line("${n.name}(node)")}
            w.line("} else {")
            w.indented {=> w.line("None")}
            w.line("}")
        }
        w.blank()
        w.block("public prop syntax: ${NODE_TYPE}") {=> w.block("get()") {=> w.line("node")}}
        for (f in n.fields) {
            w.blank()
            emitField(w, n.name, f, sets)
        }
        w.blank()
        // a view prints as the text of its node; two are equal when they view one node, which is all it holds
        w.block("public func toString(): String") {=> w.line("node.text()")}
    }
}

func emitField(w: CodeWriter, owner: String, f: FieldIr, sets: ArrayList<(String, Array<String>)>): Unit {
    func setNamed(kinds: Array<String>): String {
        let name = "${screamingSnake(owner)}_${screamingSnake(f.name)}"
        sets.add((name, kinds))
        name
    }
    match (f) {
        case NodeField(name, typeName, access) =>
            let call = "<SyntaxKind, ${typeName}>"
            match (access) {
                case First => w.block("public func ${name}(): ?${typeName}") {=> w.line("astChild${call}(node)")}
                case Nth(i, counted) => w.block("public func ${name}(): ?${typeName}") {
                    => w.line("astNthChild${call}(node, ${i}, ${setNamed(counted)})")
                }
                case All => w.block("public func ${name}(): Iterator<${typeName}>") {
                    => w.line("astChildren${call}(node)")
                }
                case AllFrom(i, counted) => w.block("public func ${name}(): Iterator<${typeName}>") {
                    => w.line("astChildrenFrom${call}(node, ${i}, ${setNamed(counted)})")
                }
            }
        case TokenField(name, kind) => w.block("public func ${name}(): ?${TOKEN_TYPE}") {
            => w.line("astToken(node, SyntaxKind.${kind})")
        }
        case TokenSetField(name, kinds) => w.block("public func ${name}(): ?${TOKEN_TYPE}") {
            => w.line("astToken(node, ${setNamed(kinds)})")
        }
    }
}

func emitEnum(w: CodeWriter, model: Model, e: EnumIr): Unit {
    w.doc(e.doc)
    w.block("public enum ${e.name} <: AstNode<SyntaxKind, ${e.name}> & Equatable<${e.name}> & Hashable & ToString") {
        =>
        for (v in e.variants) {
            w.line("| ${v.name}(${v.typeName})")
        }
        w.blank()
        w.block("public static func canCast(kind: SyntaxKind): Bool") {
            => w.block("match (kind)") {
                =>
                let kinds = model.kindsOf(e.name).map {k => "SyntaxKind.${k}"}
                w.wrapped("case ", kinds, " |", " => true", leading: true)
                w.line("case _ => false")
            }
        }
        w.blank()
        w.block("public static func cast(node: ${NODE_TYPE}): ?${e.name}") {
            =>
            if (e.variants.all {v => !model.isEnum(v.typeName)}) {
                w.block("match (node.kind)") {
                    =>
                    for (v in e.variants) {
                        w.line("case SyntaxKind.${v.typeName} => ${v.name}(${v.typeName}(node))")
                    }
                    w.line("case _ => None")
                }
            } else {
                for (v in e.variants) {
                    if (model.isEnum(v.typeName)) {
                        w.block("if (let Some(it) <- ${v.typeName}.cast(node))") {=> w.line("return ${v.name}(it)")}
                    } else {
                        w.block("if (node.kind == SyntaxKind.${v.typeName})") {
                            => w.line("return ${v.name}(${v.typeName}(node))")
                        }
                    }
                }
                w.line("None")
            }
        }
        w.blank()
        w.block("public prop syntax: ${NODE_TYPE}") {
            => w.block("get()") {
                => w.block("match (this)") {
                    => for (v in e.variants) {
                        w.line("case ${v.name}(it) => it.syntax")
                    }
                }
            }
        }
        w.blank()
        // not derived: two variants may view one node (a macro call on a declaration is a `Decl` and an `Expr`)
        w.block("public operator func ==(other: ${e.name}): Bool") {=> w.line("syntax == other.syntax")}
        w.blank()
        w.block("public operator func !=(other: ${e.name}): Bool") {=> w.line("syntax != other.syntax")}
        w.blank()
        w.block("public func hashCode(): Int64") {=> w.line("syntax.hashCode()")}
        w.blank()
        w.block("public func toString(): String") {=> w.line("syntax.text()")}
    }
}
