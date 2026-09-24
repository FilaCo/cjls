package loupe.syntax

import calca.*
import calca.macros.*
import cjsyntax.CjParse
import cjsyntax.parse as parseText
import loupe.db.*

/**
 * The file's tree. Remembered until its text changes, and a text changed into one that parses the
 * same leaves what read the tree alone, since `Parse` is `Equatable`.
 */
@CalcaTracked
public func parse(db: RootDatabase, file: SourceFile): CjParse {
    parseText(file.text(db).toString())
}
