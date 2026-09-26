package loupe.syntax

import calca.*
import calca.macros.*
import cjsyntax.CjParse
import cjsyntax.parse as parseText
import loupe.db.*

/**
 * The file's tree. Remembered until its text changes, and a text changed into one that parses the
 * same leaves what read the tree alone, since `Parse` is `Equatable`.
 *
 * Only the trees of the 128 files parsed last are kept from one revision to the next: a tree is the
 * largest thing the analysis holds, and parsing is cheap. What read an evicted tree is verified
 * without parsing it again. So a query result never holds a node, only pointers to one (A11), or
 * it keeps the whole tree alive.
 */
@CalcaTracked[lru: 128]
public func parse(db: AnalysisDatabase, file: SourceFile): CjParse {
    parseText(file.text(db).toString())
}
