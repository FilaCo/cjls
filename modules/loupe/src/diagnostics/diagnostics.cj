package loupe.diagnostics

import std.deriving.*
import calca.*
import calca.macros.*
import loupe.db.*
import loupe.syntax.parse
import ginkgo.TextRange

@CalcaTracked
public func diagnostics(db: AnalysisDatabase, file: SourceFile): Array<Diagnostic> {
    parse(db, file)
        .errors
        .map {syntaxError => Diagnostic(DiagnosticSeverity.Error, syntaxError.message, syntaxError.range)}
}

@Derive[Equatable]
public struct Diagnostic {
    public Diagnostic(public let severity: DiagnosticSeverity, public let message: String, public let range: TextRange) {}
}

@Derive[Equatable, Hashable]
public enum DiagnosticSeverity {
    | Error
}
