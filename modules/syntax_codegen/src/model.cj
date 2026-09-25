package syntax_codegen

import std.collection.*
import std.deriving.*

@Derive[Equatable]
enum KindCategory {
    | Trivia
    | Special
    | Punctuation
    | GluedPunctuation
    | Token
    | Keyword
    | Node
}

/**
 * One variant of the kind enum, and what its methods say about it.
 */
struct KindInfo {
    KindInfo(
        let name!: String,
        let category!: KindCategory,
        let doc!: Array<String> = [],
        let text!: ?String = None,
        let contextual!: Bool = false,
        let word!: Bool = false
    ) {}

    func isToken(): Bool {
        match (category) {
            case Node => false
            case _ => true
        }
    }
}

/**
 * How an accessor finds a child node.
 */
enum ChildAccess {
    /** the first child that is one */
    | First
    /** among the children of these kinds, the one at this index */
    | Nth(Int64, Array<String>)
    /** every child that is one */
    | All
    /** every child that is one, but for the first ones of these kinds */
    | AllFrom(Int64, Array<String>)
}

enum FieldIr {
    | NodeField(String, String, ChildAccess)
    | TokenField(String, String)
    | TokenSetField(String, Array<String>)

    prop name: String {
        get() {
            match (this) {
                case NodeField(n, _, _) => n
                case TokenField(n, _) => n
                case TokenSetField(n, _) => n
            }
        }
    }
}

struct NodeIr {
    NodeIr(let name: String, let doc: Array<String>, let fields: Array<FieldIr>, let handWritten: Array<String>) {}
}

struct VariantIr {
    VariantIr(let name: String, let typeName: String) {}
}

struct EnumIr {
    EnumIr(let name: String, let doc: Array<String>, let variants: Array<VariantIr>) {}
}

/**
 * Everything the output is made of: the kinds in order, and the typed views of the grammar.
 */
class Model {
    Model(
        let kinds: Array<KindInfo>,
        let nodes: Array<NodeIr>,
        let enums: Array<EnumIr>,
        let grammar: Grammar,
        let tokenKinds: HashMap<String, String>
    ) {}

    func isEnum(name: String): Bool {
        enums.any {e => e.name == name}
    }

    func enumOf(name: String): ?EnumIr {
        for (e in enums) {
            if (e.name == name) {
                return e
            }
        }
        None
    }

    /**
     * The node kinds a view of `name` can be: its own, or its variants', all the way down.
     */
    func kindsOf(name: String): Array<String> {
        match (enumOf(name)) {
            case Some(e) =>
                let result = ArrayList<String>()
                for (v in e.variants) {
                    result.add(all: kindsOf(v.typeName))
                }
                result.toArray()
            case None => [name]
        }
    }
}

/**
 * The name of the pseudo-token matching any token, for nodes holding raw tokens.
 */
let ANY_TOKEN = "AnyToken"

func buildModel(file: KindsFile, grammar: Grammar): Model {
    let kinds = ArrayList<KindInfo>()
    func addAll(entries: ?Array<KindEntry>, category: KindCategory) {
        for (e in entries ?? []) {
            kinds.add(
                KindInfo(
                    name: e.name,
                    category: category,
                    doc: docLines(e.doc),
                    text: e.text,
                    contextual: e.contextual ?? false,
                    word: e.word ?? false
                ))
        }
    }
    addAll(file.trivia, Trivia)
    addAll(file.special, Special)
    addAll(file.punctuation, Punctuation)
    addAll(file.gluedPunctuation, GluedPunctuation)
    addAll(file.tokens, Token)
    addAll(file.keywords, Keyword)
    addAll(file.nodes, Node)
    checkKinds(kinds)

    // a token is named by its kind's name, or by its text: the first kind spelled so, punctuation and keywords
    // coming first (`}` is `RBrace`, and the end of an interpolation `'InterpolationEnd'`)
    let tokenKinds = HashMap<String, String>()
    for (k in kinds where k.isToken()) {
        tokenKinds.add(k.name, k.name)
    }
    for (k in kinds where k.isToken()) {
        if (let Some(text) <- k.text && !tokenKinds.contains(text)) {
            tokenKinds.add(text, k.name)
        }
    }

    let enums = ArrayList<EnumIr>()
    for (r in grammar.rules) {
        if (let Some(variants) <- enumVariants(r.rule)) {
            enums.add(EnumIr(r.name, r.doc, variants))
        } else {
            kinds.add(KindInfo(name: r.name, category: Node, doc: r.doc))
        }
    }
    checkKinds(kinds)
    let known = HashSet<String>(grammar.rules.map {r => r.name})
    for (r in grammar.rules) {
        checkRefs(r.name, r.rule, known, tokenKinds)
    }
    let model = Model(kinds.toArray(), [], enums.toArray(), grammar, tokenKinds)
    checkVariantNames(model)
    let nodes = ArrayList<NodeIr>()
    for (r in grammar.rules where !model.isEnum(r.name)) {
        nodes.add(lowerNode(model, r))
    }
    Model(model.kinds, nodes.toArray(), model.enums, grammar, tokenKinds)
}

func docLines(doc: ?String): Array<String> {
    match (doc) {
        case Some(d) => [d]
        case None => []
    }
}

func checkKinds(kinds: ArrayList<KindInfo>): Unit {
    let seen = HashSet<String>()
    for (k in kinds) {
        if (!seen.add(k.name)) {
            throw ConfigException("`${k.name}` is declared twice")
        }
    }
}

/**
 * The variants of a rule that only lists nodes, each one maybe labeled with its variant's name; `None` for a
 * rule that makes a node.
 */
func enumVariants(rule: Rule): ?Array<VariantIr> {
    let alts = match (rule) {
        case Alt(alts) => alts
        case _ => return None
    }
    let variants = ArrayList<VariantIr>()
    for (alt in alts) {
        match (alt) {
            case NodeRef(n) => variants.add(VariantIr("As${n}", n))
            case Labeled(label, NodeRef(n)) => variants.add(VariantIr(label, n))
            case _ => return None
        }
    }
    variants.toArray()
}

func checkRefs(owner: String, rule: Rule, known: HashSet<String>, tokenKinds: HashMap<String, String>): Unit {
    match (rule) {
        case NodeRef(n) where !known.contains(n) => throw GrammarException("`${owner}` refers to `${n}`, which has no rule")
        case NodeRef(_) => ()
        case TokenRef(t) where t != ANY_TOKEN && !tokenKinds.contains(t) =>
            throw GrammarException("`${owner}` refers to the token '${t}', which the kinds file does not declare")
        case TokenRef(_) => ()
        case _ => for (r in rule.children()) {
            checkRefs(owner, r, known, tokenKinds)
        }
    }
}

/**
 * An enum variant is in scope throughout its package, unqualified: one named like a type there would hide it.
 */
func checkVariantNames(model: Model): Unit {
    let types = HashSet<String>()
    for (k in model.kinds where !k.isToken()) {
        types.add(k.name)
    }
    for (e in model.enums) {
        types.add(e.name)
    }
    for (e in model.enums) {
        for (v in e.variants where types.contains(v.name)) {
            throw GrammarException("the variant `${v.name}` of `${e.name}` would hide the type of that name: label it")
        }
    }
}

/**
 * Where a child stands in its rule. `alts` is the path of alternatives it is under, as (alternative, branch):
 * two children that took different branches of one alternative never both appear.
 */
struct Occurrence {
    Occurrence(
        let label: ?String,
        let node: ?String,
        let tokens: Array<String>,
        let optional: Bool,
        let many: Bool,
        let alts: Array<(Int64, Int64)>,
        let order: Int64
    ) {}

    func excludes(other: Occurrence): Bool {
        for ((alt, branch) in alts) {
            for ((otherAlt, otherBranch) in other.alts) {
                if (alt == otherAlt && branch != otherBranch) {
                    return true
                }
            }
        }
        false
    }

    /**
     * Whether a tree without errors always has it, once.
     */
    func mandatory(): Bool {
        !optional && !many && alts.isEmpty()
    }
}

class OccurrenceCollector {
    let occurrences = ArrayList<Occurrence>()
    var nextAlt = 0

    OccurrenceCollector(let model: Model, let owner: String) {}

    func collect(rule: Rule, label: ?String, optional: Bool, many: Bool, alts: Array<(Int64, Int64)>): Unit {
        match (rule) {
            case NodeRef(n) => occurrences.add(Occurrence(label, n, [], optional, many, alts, occurrences.size))
            case TokenRef(t) where t == ANY_TOKEN => ()
            case TokenRef(t) =>
                let kind = model.tokenKinds[t]
                occurrences.add(Occurrence(label, None, [kind], optional, many, alts, occurrences.size))
            case Labeled(l, r) =>
                match (label) {
                    case Some(outer) => throw GrammarException("`${owner}`: `${l}` is labeled inside `${outer}`")
                    case None => ()
                }
                if (let Some(tokens) <- tokensOnly(r)) {
                    occurrences.add(Occurrence(l, None, tokens, true, false, alts, occurrences.size))
                } else {
                    collect(r, l, optional, many, alts)
                }
            case Seq(rs) => for (r in rs) {
                collect(r, label, optional, many, alts)
            }
            case Alt(rs) =>
                let id = nextAlt
                nextAlt++
                for (i in 0..rs.size) {
                    let path = ArrayList<(Int64, Int64)>(alts)
                    path.add((id, i))
                    collect(rs[i], label, optional, many, path.toArray())
                }
            case Opt(r) => collect(r, label, true, many, alts)
            case Rep(r) => collect(r, label, true, true, alts)
        }
    }

    /**
     * The kinds of the tokens `rule` is made of, if it is made of tokens alone.
     */
    func tokensOnly(rule: Rule): ?Array<String> {
        match (rule) {
            case TokenRef(t) where t != ANY_TOKEN => [model.tokenKinds[t]]
            case TokenRef(_) | NodeRef(_) | Labeled(_, _) => None
            case _ =>
                let result = ArrayList<String>()
                for (r in rule.children()) {
                    result.add(all: tokensOnly(r) ?? return None)
                }
                result.toArray()
        }
    }
}

/**
 * The accessors of the node `def` makes: one per node child, named after its label or its type, and one per
 * kind of token; a labeled group of tokens is one accessor for any of them.
 *
 * A child is found by its position among the children that could be taken for it: those whose types share a
 * kind with its own, in a branch the grammar allows together with it. When one of those before it may be
 * missing, or one after it may be there while it is not, its position says nothing, and the accessor is written
 * by hand (`handWritten`).
 */
func lowerNode(model: Model, def: RuleDef): NodeIr {
    let collector = OccurrenceCollector(model, def.name)
    collector.collect(def.rule, None, false, false, [])
    let occs = collector.occurrences

    // fields in the order first met
    let fieldOrder = ArrayList<String>()
    let fieldOccs = HashMap<String, ArrayList<Occurrence>>()
    for (o in occs) {
        let key = fieldKey(o)
        if (!fieldOccs.contains(key)) {
            fieldOrder.add(key)
            fieldOccs.add(key, ArrayList<Occurrence>())
        }
        fieldOccs[key].add(o)
    }

    let fields = ArrayList<FieldIr>()
    let handWritten = ArrayList<String>()
    for (key in fieldOrder) {
        let own = fieldOccs[key]
        let first = own[0]
        match ((first.label, first.node)) {
            case (Some(l), None) => fields.add(TokenSetField(l, dedup(first.tokens)))
            case (None, None) => fields.add(TokenField(tokenFieldName(first.tokens[0]), first.tokens[0]))
            case (_, Some(typeName)) =>
                let many = isMany(own)
                let name = first.label ?? nodeFieldName(typeName, many)
                if (let Some(access) <- childAccess(model, own, many, occs)) {
                    fields.add(NodeField(name, typeName, access))
                } else {
                    handWritten.add(name)
                }
        }
    }
    checkFieldNames(def.name, fields)
    NodeIr(def.name, def.doc, fields.toArray(), handWritten.toArray())
}

/**
 * What groups the occurrences of one accessor: its label, else the type of node, else the kind of token.
 */
func fieldKey(o: Occurrence): String {
    match ((o.label, o.node)) {
        case (Some(l), _) => l
        case (None, Some(n)) => n
        case (None, None) => "'${o.tokens[0]}"
    }
}

/**
 * Whether a tree may hold several of a child: one under a repetition, or met twice in branches allowed together.
 */
func isMany(own: ArrayList<Occurrence>): Bool {
    if (own.any {o => o.many}) {
        return true
    }
    for (i in 0..own.size) {
        for (j in i + 1..own.size) {
            if (!own[i].excludes(own[j])) {
                return true
            }
        }
    }
    false
}

func nodeFieldName(typeName: String, many: Bool): String {
    let base = lowerFirst(typeName)
    if (many) {
        "${base}s"
    } else if (base == "type") {
        "ty"
    } else {
        base
    }
}

func tokenFieldName(kind: String): String {
    let base = if (kind.endsWith("Kw")) {
        kind[..kind.size - 2]
    } else {
        kind
    }
    "${lowerFirst(base)}Token"
}

func lowerFirst(s: String): String {
    if (s.isEmpty()) {
        return s
    }
    let bytes = s.toArray()
    if (bytes[0] >= b'A' && bytes[0] <= b'Z') {
        bytes[0] = bytes[0] + 32
    }
    String.fromUtf8(bytes)
}

func dedup(items: Array<String>): Array<String> {
    let seen = HashSet<String>()
    items.filter {i => seen.add(i)}
}

/**
 * Cangjie's keywords that start lowercase: no accessor can be named so.
 */
let KEYWORDS: Array<String> = ["as", "abstract", "break", "case", "catch", "class", "const", "continue", "do", "else",
    "enum", "extend", "false", "finally", "for", "foreign", "func", "if", "import", "in", "init", "inout", "interface",
    "is", "let", "macro", "main", "match", "mut", "open", "operator", "override", "package", "private", "prop",
    "protected", "public", "quote", "redef", "return", "sealed", "spawn", "static", "struct", "super",
    "synchronized", "this", "throw", "true", "try", "type", "unsafe", "var", "where", "while"]

func checkFieldNames(owner: String, fields: ArrayList<FieldIr>): Unit {
    let reserved = ["syntax", "cast", "canCast", "hashCode", "toString", "node"]
    for (f in fields where reserved.contains(f.name) || KEYWORDS.contains(f.name)) {
        throw GrammarException("`${owner}`: an accessor cannot be named `${f.name}`: label it")
    }
}

func childAccess(model: Model, own: ArrayList<Occurrence>, many: Bool, all: ArrayList<Occurrence>): ?ChildAccess {
    let first = own[0]
    let typeName = first.node.getOrThrow()
    let ownKinds = HashSet<String>(model.kindsOf(typeName))
    let rivals = all.filter {
        o => match (o.node) {
            case Some(n) => fieldKey(o) != fieldKey(first) && !o.excludes(first) &&
                model.kindsOf(n).any {k => ownKinds.contains(k)}
            case None => false
        }
    }
    let before = rivals.filter {o => o.order < first.order}
    let after = rivals.filter {o => o.order > first.order}
    if (!before.all {o => o.mandatory()}) {
        return None
    }
    if (!after.isEmpty() && (many || !(own.size == 1 && first.mandatory()))) {
        return None
    }
    let counted = ArrayList<String>(model.kindsOf(typeName))
    for (o in before) {
        for (k in model.kindsOf(o.node.getOrThrow()) where !counted.contains(k)) {
            counted.add(k)
        }
    }
    let n = before.size
    if (many) {
        if (n == 0) {
            All
        } else {
            AllFrom(n, counted.toArray())
        }
    } else if (n == 0) {
        First
    } else {
        Nth(n, counted.toArray())
    }
}
