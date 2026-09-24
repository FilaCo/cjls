package syntax_codegen

import std.collection.*
import std.env.getVariable
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.*
import cjsyntax.*
import cjsyntax.ast.{RangeExpr, Stmt, Expr}

/**
 * A child as a rule sees it: a node or a token, and its kind's name.
 */
struct Child {
    Child(let isNode: Bool, let kind: String) {}
}

/**
 * Checks trees against the grammar the views are generated from: an accessor finds what the grammar says only if
 * the parser puts it there.
 *
 * A tree without errors must match the grammar exactly. In one with errors, the parser may have left out any
 * part of a node and put an `ErrorNode` anywhere, so a node there must only hold nothing the grammar does not
 * allow, in no order it does not allow.
 */
class Conformance {
    let model: Model
    let rules = HashMap<String, Rule>()

    init() {
        let generated = generate(Path(KINDS_FILE))
        model = generated.model
        for (r in model.grammar.rules where !model.isEnum(r.name)) {
            rules.add(r.name, r.rule)
        }
    }

    /**
     * Every node of `root` that does not match its rule, with its children.
     */
    func violations(root: CjSyntaxNode, strict: Bool): ArrayList<String> {
        let result = ArrayList<String>()
        for (node in root.descendants()) {
            let kind = node.kind.toString()
            let rule = rules.get(kind) ?? continue
            let children = ArrayList<Child>()
            for (el in node.childrenWithTokens()) {
                match (el) {
                    case SyntaxElement.Node(n) where !strict && n.kind == ErrorNode => ()
                    case SyntaxElement.Node(n) => children.add(Child(true, n.kind.toString()))
                    case SyntaxElement.Token(t) where t.kind.isTrivia() => ()
                    case SyntaxElement.Token(t) => children.add(Child(false, t.kind.toString()))
                }
            }
            let ends = matches(rule, children, 0, strict)
            if (!ends.contains(children.size)) {
                let shown = children.toArray().map {c => if (c.isNode) { c.kind } else { "'${c.kind}'" }}
                result.add("${kind} at ${node.textRange}: ${String.join(shown, delimiter: " ")}")
            }
        }
        result
    }

    /**
     * Where `rule` can end, starting at `pos` among `children`.
     */
    func matches(rule: Rule, children: ArrayList<Child>, pos: Int64, strict: Bool): HashSet<Int64> {
        let result = HashSet<Int64>()
        match (rule) {
            case NodeRef(n) =>
                if (pos < children.size && children[pos].isNode && model.kindsOf(n).contains(children[pos].kind)) {
                    result.add(pos + 1)
                }
                if (!strict) {
                    result.add(pos)
                }
            case TokenRef(t) =>
                if (pos < children.size && !children[pos].isNode &&
                    (t == ANY_TOKEN || model.tokenKinds[t] == children[pos].kind)) {
                    result.add(pos + 1)
                }
                if (!strict) {
                    result.add(pos)
                }
            case Labeled(_, r) => result.add(all: matches(r, children, pos, strict))
            case Seq(rs) =>
                result.add(pos)
                for (r in rs) {
                    let next = HashSet<Int64>()
                    for (p in result) {
                        next.add(all: matches(r, children, p, strict))
                    }
                    result.clear()
                    result.add(all: next)
                }
            case Alt(rs) => for (r in rs) {
                result.add(all: matches(r, children, pos, strict))
            }
            case Opt(r) =>
                result.add(pos)
                result.add(all: matches(r, children, pos, strict))
            case Rep(r) =>
                result.add(pos)
                var frontier = [pos]
                while (!frontier.isEmpty()) {
                    let next = ArrayList<Int64>()
                    for (p in frontier) {
                        for (e in matches(r, children, p, strict) where !result.contains(e)) {
                            result.add(e)
                            next.add(e)
                        }
                    }
                    frontier = next.toArray()
                }
        }
        result
    }

    /**
     * The violations in the file at `path`, each prefixed with it.
     */
    func check(path: Path): ArrayList<String> {
        let text = String.fromUtf8(File.readFrom(path))
        let parse = parse(text)
        let found = violations(parse.syntaxNode(), parse.errors.isEmpty())
        let result = ArrayList<String>()
        for (v in found) {
            result.add("${path}: ${v}")
        }
        result
    }
}

/**
 * The `.cj` files under `dir`, all the way down.
 */
func cjFilesUnder(dir: Path, into: ArrayList<Path>): Unit {
    for (info in Directory.readFrom(dir)) {
        if (info.isDirectory()) {
            cjFilesUnder(info.path, into)
        } else if (info.path.toString().endsWith(".cj")) {
            into.add(info.path)
        }
    }
}

func conformanceOf(text: String): Array<String> {
    let parse = parse(text)
    printed(Conformance().violations(parse.syntaxNode(), parse.errors.isEmpty()).toArray())
}

/**
 * `violations`, printed too: what a failed expectation does not show.
 */
func printed(violations: Array<String>): Array<String> {
    for (v in violations) {
        println("violation: ${v}")
    }
    violations
}

@Test
class ConformanceTest {
    @TestCase
    func everyFileOfThisRepositoryHasTheShapeTheGrammarSays() {
        // arrange
        let files = ArrayList<Path>()
        for (info in Directory.readFrom(Path("modules"))) {
            if (info.isDirectory() && exists(info.path.join("src"))) {
                cjFilesUnder(info.path.join("src"), files)
            }
        }
        let sut = Conformance()

        // act
        let violations = ArrayList<String>()
        for (f in files) {
            violations.add(all: sut.check(f))
        }

        // assert
        @Expect(files.size > 100)
        @Expect(printed(violations.toArray()[..min(violations.size, 20)]), Array<String>())
    }

    @TestCase
    func aNodeThatHoldsWhatItsRuleDoesNotAllowIsCaught() {
        // arrange
        let sut = Conformance()
        let children = ArrayList<Child>([Child(false, "IfKw"), Child(false, "LParen")])

        // act & assert
        @Expect(sut.matches(parseGrammar("A = 'if' '('").rules[0].rule, children, 0, true).contains(2))
        @Expect(!sut.matches(parseGrammar("A = '(' 'if'").rules[0].rule, children, 0, true).contains(2))
        @Expect(!sut.matches(parseGrammar("A = 'if' '(' ')'").rules[0].rule, children, 0, true).contains(2))
        @Expect(sut.matches(parseGrammar("A = 'if' '(' ')'").rules[0].rule, children, 0, false).contains(2))
    }

    @TestCase
    func treesWithErrorsHoldNothingTheGrammarDoesNotAllow() {
        // act & assert
        @Expect(conformanceOf("func f(a: Int64, { x }"), Array<String>())
        @Expect(conformanceOf("main() { if (a { b } else }"), Array<String>())
        @Expect(conformanceOf("class A { let }\nx +"), Array<String>())
    }

    /**
     * The compiler's test suite, or any other tree of sources, when `CJSYNTAX_CORPUS` names one:
     * `CJSYNTAX_CORPUS=~/Projects/cangjie_test cjpm test '--filter=ConformanceTest.*'`.
     */
    @TestCase
    func aCorpusNamedByTheEnvironmentHasTheShapeTheGrammarSays() {
        // arrange
        let dir = getVariable("CJSYNTAX_CORPUS") ?? return
        let files = ArrayList<Path>()
        cjFilesUnder(Path(dir), files)
        let sut = Conformance()
        let byKind = HashMap<String, Int64>()
        let examples = HashMap<String, String>()

        // act
        for (f in files) {
            let found = try {
                sut.check(f)
            } catch (e: Exception) {
                ArrayList<String>(["${f}: ${e}"])
            }
            for (v in found) {
                let kind = v[v.indexOf(": ").getOrThrow() + 2..].split(" ")[0]
                byKind[kind] = (byKind.get(kind) ?? 0) + 1
                if (!examples.contains(kind)) {
                    examples[kind] = v
                }
            }
        }

        // assert
        let report = ArrayList<String>()
        for ((kind, count) in byKind) {
            report.add("${count} x ${examples[kind]}")
        }
        println("checked ${files.size} files")
        @Expect(printed(report.toArray()), Array<String>())
    }

    @TestCase
    func handWrittenAccessorsAreSeenOutsideTheirPackage() {
        // arrange
        let root = parse("main() {\na[1..=n : 2]\n}").syntaxNode()
        let range = root.descendants().filterMap {n => RangeExpr.cast(n)}.next().getOrThrow()

        // act & assert
        @Expect(range.start().map {e => e.toString()}, Some("1"))
        @Expect(range.end().map {e => e.toString()}, Some("n"))
        @Expect(range.step().map {e => e.toString()}, Some("2"))
    }
}
