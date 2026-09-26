package loupe.syntax

import std.collection.*
import std.ref.*
import std.runtime.gc
import std.unittest.*
import std.unittest.testmacro.*
import calca.*
import calca.macros.*
import cjsyntax.*
import cjsyntax.ast.FuncDecl
import ginkgo.*
import rope.Rope
import loupe.db.*
import loupe.vfs.FileId

/**
 * How many trees `parse` keeps, as its `lru` says.
 */
const PARSE_LRU = 128

/**
 * What a query that breaks A11 returns: a node, and with it the whole tree.
 */
@CalcaTracked
func rootOf(db: AnalysisDatabase, file: SourceFile): CjSyntaxNode {
    parse(db, file).syntaxNode()
}

/**
 * What a query keeping to A11 returns: pointers to the functions of the file.
 */
@CalcaTracked
func functions(db: AnalysisDatabase, file: SourceFile): Array<AstPtr<SyntaxKind, FuncDecl>> {
    let root = parse(db, file).syntaxNode()
    collectArray(root.descendants().filterMap {node => FuncDecl.cast(node)}.map {decl => AstPtr(decl)})
}

func functionNames(db: AnalysisDatabase, file: SourceFile): Array<String> {
    let root = parse(db, file).syntaxNode()
    functions(db, file).map {ptr => ptr.toNode(root).name()?.toString() ?? ""}
}

/**
 * A reference to `file`'s tree that does not keep it alive; made here, so no variable of the test holds it.
 */
func weakTree(db: AnalysisDatabase, file: SourceFile): WeakRef<GreenNode<SyntaxKind>> {
    WeakRef(parse(db, file).green, CleanupPolicy.EAGER)
}

/**
 * Whether the runtime frees what `ref` refers to. `gc` returns before weak references are cleared (measured,
 * 1.3.0-alpha: still set right after `gc(heavy: true)`, however many times, and cleared a millisecond later), so
 * this waits a little after each collection, a bounded number of times.
 */
func isFreed<T>(ref: WeakRef<T>): Bool where T <: Object {
    for (_ in 0..20) {
        gc(heavy: true)
        sleep(Duration.millisecond * 10)
        if (ref.value.isNone()) {
            return true
        }
    }
    false
}

@Test
class ParseLruTest {
    @TestCase
    func anEvictedTreeIsFreed() {
        // arrange
        let db = AnalysisDatabase()
        let (file, other) = files(db)
        let tree = weakTree(db, file)
        parseOthers(db)

        // act
        db.setFileText(other, Rope("changed"))

        // assert
        @Expect(isFreed(tree))
        keepAlive(db, file)
    }

    @TestCase
    func aResultHoldingANodeKeepsAnEvictedTreeAlive() {
        // arrange
        let db = AnalysisDatabase()
        let (file, other) = files(db)
        let tree = weakTree(db, file)
        rootOf(db, file)
        parseOthers(db)

        // act
        db.setFileText(other, Rope("changed"))

        // assert
        @Expect(!isFreed(tree))
        keepAlive(db, file)
    }

    @TestCase
    func pointersKeptOutliveTheirTreeAndResolveOnTheOneParsedAgain() {
        // arrange
        let db = AnalysisDatabase()
        let (file, other) = files(db)
        let before = parse(db, file)
        let ptrs = functions(db, file)
        parseOthers(db)
        db.setFileText(other, Rope("changed"))

        // act
        let names = functionNames(db, file)
        let after = parse(db, file)

        // assert
        @Expect(names, ["f", "g"])
        @Expect(!refEq(before.green, after.green))
        @Expect(before, after)
        @Expect(functions(db, file), ptrs)
    }

    /**
     * Uses the database once the runtime has collected: a database no longer used is garbage too, and with it
     * everything it holds, so a tree would be freed whatever calca did.
     */
    private func keepAlive(db: AnalysisDatabase, file: SourceFile): Unit {
        @Expect(rootOf(db, file).text(), file.text(db).toString())
    }

    /**
     * The file the test looks at, and one no query reads: setting it opens a revision.
     */
    private func files(db: AnalysisDatabase): (SourceFile, FileId) {
        let file = db.setFileText(FileId(0), Rope("func f() {}\nfunc g() {}\n"))
        let other = FileId(1)
        db.setFileText(other, Rope(""))
        (file, other)
    }

    /**
     * Parses as many other files as `parse` keeps trees, so the next write evicts every tree parsed before.
     */
    private func parseOthers(db: AnalysisDatabase): Unit {
        for (i in 0..PARSE_LRU) {
            parse(db, db.setFileText(FileId(100 + i), Rope("let x${i} = ${i}")))
        }
    }
}
