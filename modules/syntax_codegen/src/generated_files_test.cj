package syntax_codegen

import std.collection.*
import std.env.getTempDirectory
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*

let KINDS_FILE = "modules/cjsyntax/syntax_kinds.toml"

/**
 * rust-analyzer's `sourcegen` check: a change to the kinds file or the grammar that was not generated fails here,
 * and with it `pre-push`.
 */
@Test
class GeneratedFilesTest {
    @TestCase
    func theCheckedInFilesAreWhatTheGeneratorMakes() {
        // arrange
        let generated = generate(Path(KINDS_FILE))
        let dir = Directory.createTemp(getTempDirectory())
        let stale = ArrayList<String>()

        // act
        try {
            for (file in generated.files) {
                let fresh = dir.join(file.path.fileName)
                writeFormatted(fresh, file.contents)
                if (File.readFrom(fresh) != File.readFrom(file.path)) {
                    stale.add("${file.path} is out of date: `cjpm build`, then `target/release/bin/syntax_codegen ${KINDS_FILE}`")
                }
            }
        } finally {
            remove(dir, recursive: true)
        }

        // assert
        @Expect(stale.toArray(), Array<String>())
    }
}
