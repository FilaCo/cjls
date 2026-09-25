package loupe

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.TextRange
import rope.Rope
import loupe.vfs.FileId
import loupe.db.AnalysisDatabase

func structureOf(text: String): Array<StructureNode> {
    let db = AnalysisDatabase()
    db.setFileText(FileId(0), Rope(text))
    fileStructure(db, FileId(0))
}

/**
 * The outline as `Kind name` lines, nested by indentation.
 */
func outline(text: String): String {
    let lines = ArrayList<String>()
    writeOutline(lines, structureOf(text), "")
    String.join(lines.toArray(), delimiter: "\n")
}

func writeOutline(lines: ArrayList<String>, nodes: Array<StructureNode>, indent: String): Unit {
    for (node in nodes) {
        lines.add("${indent}${node.kind} ${node.name}")
        writeOutline(lines, node.children, indent + "  ")
    }
}

@Test
class StructureTest {
    @TestCase
    func whatATypeDeclaresIsUnderIt() {
        // act
        let result = outline("""
            class A {
                var x: Int64 = 1
                A(let y: Int64) {}
                init() {}
                ~init() {}
                prop p: Int64 { get() { x } }
                operator func [](i: Int64): Int64 { i }
                func f() { let local = 1 }
            }
            """)

        // assert - `local` is inside a body, not an outline entry
        @Expect(result, "Class A\n  Field x\n  Constructor A\n  Constructor init\n  Finalizer ~init\n  Property p\n  Method []\n  Method f")
    }

    @TestCase
    func everyKindOfTopLevelDeclarationIsThere() {
        // act
        let result = outline("""
            package p
            import std.collection.*
            interface I { func g(): Unit }
            struct S {}
            enum E { | A | B(Int64) }
            extend<T> Array<T> <: I { func g() {} }
            type Alias = Int64
            const C = 1
            let (a, b) = (1, 2)
            @M func m() {}
            main() { 0 }
            """)

        // assert
        @Expect(result, "Interface I\n  Method g\nStruct S\nEnum E\n  EnumConstructor A\n  EnumConstructor B\nExtension Array<T>\n  Method g\nTypeAlias Alias\nConstant C\nVariable a\nVariable b\nFunction m\nMain main")
    }

    @TestCase
    func aDeclarationSpansItsDocCommentAndSelectsItsName() {
        // arrange
        let text = "// doc\nfunc f() {}\n"

        // act
        let f = structureOf(text)[0]

        // assert
        @Expect(f.range, TextRange(0, 18))
        @Expect(f.selectionRange, TextRange(12, 13))
    }

    @TestCase
    func aDeclarationWithoutANameYetIsLeftOut() {
        // act, assert
        @Expect(outline("class {\n  func f() {}\n}\nfunc g() {}"), "Function g")
    }

    @TestCase
    func aFileNeverSetHasNoStructure() {
        // act, assert
        @Expect(fileStructure(AnalysisDatabase(), FileId(7)).size, 0)
    }
}
