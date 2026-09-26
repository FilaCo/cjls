package loupe

import std.deriving.*
import std.sort.*
import ginkgo.TextRange
import loupe.vfs.FileId
import loupe.db.AnalysisDatabase
import loupe.syntax.parse

@Derive[Equatable]
public enum Severity {
    | Error
}

/**
 * Something wrong in a file. `range` is where its source put it, empty ones included, as "expected
 * `}`" at the end of a file (A12).
 */
@Derive[Equatable]
public struct Diagnostic {
    public Diagnostic(public let range: TextRange, public let severity: Severity, public let message: String) {}
}

/**
 * What is wrong in a file, in the order of the text: for now what the lexer and the parser found.
 * Empty for a file the database does not know.
 *
 * Not a query: every source of diagnostics is one (`parse`, later validation and name resolution),
 * remembered there, and this only collects their results (A11).
 */
public func diagnostics(db: AnalysisDatabase, fileId: FileId): Array<Diagnostic> {
    let file = db.sourceFile(fileId) ?? return []
    let result = parse(db, file).errors.map {error => Diagnostic(error.range, Severity.Error, error.message)}
    sort(result, stable: true, by: {a: Diagnostic, b: Diagnostic => a.range.start.compare(b.range.start)})
    result
}
