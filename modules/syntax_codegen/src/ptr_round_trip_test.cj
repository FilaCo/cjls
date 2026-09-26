package syntax_codegen

import std.collection.*
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.*
import cjsyntax.*

@Test
class PtrRoundTripTest {
    @TestCase
    func everyNodeOfThisRepositoryIsFoundAgainByItsPointer() {
        // arrange
        let files = ArrayList<Path>()
        for (info in Directory.readFrom(Path("modules"))) {
            if (info.isDirectory() && exists(info.path.join("src"))) {
                cjFilesUnder(info.path.join("src"), files)
            }
        }

        // act
        var nodes = 0
        let lost = ArrayList<String>()
        for (path in files) {
            let root = parse(String.fromUtf8(File.readFrom(path))).syntaxNode()
            for (node in root.descendants()) {
                nodes++
                let ptr = SyntaxNodePtr(node)
                if (ptr.toNode(root) != node) {
                    lost.add("${path}: ${ptr}")
                }
            }
        }

        // assert
        @Expect(nodes > 100000)
        @Expect(printed(lost.toArray()[..min(lost.size, 20)]), Array<String>())
    }
}
