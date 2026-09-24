package syntax_codegen

import std.fs.*
import stdx.serialization.serialization.*
import stdxx.serialization.*
import stdxx.deriving.*
import cjtoml.*

/**
 * One kind in the kinds file. Which fields it may have depends on its section: see `KindsFile`.
 */
@DeriveExt[Serializable]
struct KindEntry {
    KindEntry(
        let name!: String,
        let text!: ?String = None,
        let doc!: ?String = None,
        let contextual!: ?Bool = None,
        let word!: ?Bool = None
    ) {}
}

/**
 * The kinds file: where the grammar is, where the output goes, and the kinds of tokens and of the nodes the
 * grammar has no rule for, by section. Paths are relative to the file.
 */
@DeriveExt[Serializable]
struct KindsFile {
    KindsFile(
        let grammar!: String,
        @DeriveExtSerializable[rename: "kinds-output"] let kindsOutput!: String,
        @DeriveExtSerializable[rename: "kinds-package"] let kindsPackage!: String,
        @DeriveExtSerializable[rename: "ast-output"] let astOutput!: String,
        @DeriveExtSerializable[rename: "ast-package"] let astPackage!: String,
        let trivia!: ?Array<KindEntry> = None,
        let special!: ?Array<KindEntry> = None,
        let punctuation!: ?Array<KindEntry> = None,
        @DeriveExtSerializable[rename: "glued-punctuation"] let gluedPunctuation!: ?Array<KindEntry> = None,
        let tokens!: ?Array<KindEntry> = None,
        let keywords!: ?Array<KindEntry> = None,
        let nodes!: ?Array<KindEntry> = None
    ) {}
}

class ConfigException <: Exception {
    ConfigException(message: String) {
        super(message)
    }

    protected override func getClassName(): String {
        "ConfigException"
    }
}

/**
 * The kinds file at `path` and the grammar it names, read and checked.
 */
struct Inputs {
    Inputs(let dir!: Path, let kinds!: KindsFile, let grammar!: Grammar) {}

    static func load(path: Path): Inputs {
        let kinds = unmarshal<KindsFile>(path.toString())
        let dir = if (path.parent.isEmpty()) {
            Path(".")
        } else {
            path.parent
        }
        let grammarText = String.fromUtf8(File.readFrom(dir.join(kinds.grammar)))
        Inputs(dir: dir, kinds: kinds, grammar: parseGrammar(grammarText))
    }
}
