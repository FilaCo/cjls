package loupe

import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.TextRange
import rope.Rope
import loupe.vfs.FileId
import loupe.db.AnalysisDatabase

func diagnosticsOf(text: String): Array<Diagnostic> {
    let db = AnalysisDatabase()
    db.setFileText(FileId(0), Rope(text))
    diagnostics(db, FileId(0))
}

@Test
class DiagnosticsTest {
    @TestCase
    func aFileThatParsesHasNone() {
        // act
        let result = diagnosticsOf("func f(): Int64 { 1 }\n")

        // assert
        @Expect(result.size, 0)
    }

    @TestCase
    func aSyntaxErrorIsAnErrorWhereTheParserPutIt() {
        // act
        let result = diagnosticsOf("class A {")

        // assert
        @Expect(result.size, 1)
        @Expect(result[0].range, TextRange(9, 9))
        @Expect(result[0].severity == Severity.Error)
        @Expect(result[0].message, "expected RBrace")
    }

    @TestCase
    func theyComeInTheOrderOfTheText() {
        // act
        let result = diagnosticsOf("let a = \nlet b = \n")

        // assert
        @Expect(result.map {diagnostic => diagnostic.range}, [TextRange(7, 7), TextRange(16, 16)])
    }

    @TestCase
    func aFileTheDatabaseDoesNotKnowHasNone() {
        // arrange
        let db = AnalysisDatabase()

        // act
        let result = diagnostics(db, FileId(0))

        // assert
        @Expect(result.size, 0)
    }
}
