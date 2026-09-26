package cjls.handlers

import rope.{Encoding, Rope}
import loupe.{StructureKind, StructureNode}
import loupe.diagnostics.{Diagnostic, DiagnosticSeverity}
import cjls.lsp_types.{Range as LspRange, Diagnostic as LspDiagnostic, DiagnosticSeverity as LspDiagnosticSeverity, 
    SymbolKind, Position, DocumentSymbol, StringOrMarkupContent}

/**
 * `start..end`, byte offsets into `text`, as the client counts: lines and columns of `encoding`.
 * `text` has to be the one the offsets were computed on, the snapshot's.
 */
func lspRange(text: Rope, start: Int64, end: Int64, encoding: Encoding): LspRange {
    LspRange(start: lspPosition(text, start, encoding), end: lspPosition(text, end, encoding))
}

func lspPosition(text: Rope, offset: Int64, encoding: Encoding): Position {
    let position = text.positionOf(offset, encoding)
    Position(line: UInt32(position.line), character: UInt32(position.column))
}

func documentSymbol(text: Rope, node: StructureNode, encoding: Encoding): DocumentSymbol {
    DocumentSymbol(
        name: node.name,
        kind: symbolKind(node.kind),
        range: lspRange(text, node.range.start, node.range.end, encoding),
        selectionRange: lspRange(text, node.selectionRange.start, node.selectionRange.end, encoding),
        children: node.children.map {child => documentSymbol(text, child, encoding)}
    )
}

/**
 * LSP has no kind for an extension, a macro or `main`: they go as rust-analyzer sends an `impl`,
 * a macro and a function.
 */
func symbolKind(kind: StructureKind): SymbolKind {
    match (kind) {
        case StructureKind.Class => SymbolKind.Class
        case StructureKind.Interface => SymbolKind.Interface
        case StructureKind.Struct => SymbolKind.Struct
        case StructureKind.Enum => SymbolKind.Enum
        case StructureKind.EnumConstructor => SymbolKind.EnumMember
        case StructureKind.Extension => SymbolKind.Object
        case StructureKind.Function | StructureKind.Macro | StructureKind.Main => SymbolKind.Function
        case StructureKind.Method | StructureKind.Finalizer => SymbolKind.Method
        case StructureKind.Constructor => SymbolKind.Constructor
        case StructureKind.Property => SymbolKind.Property
        case StructureKind.Variable => SymbolKind.Variable
        case StructureKind.Field => SymbolKind.Field
        case StructureKind.Constant => SymbolKind.Constant
        case StructureKind.TypeAlias => SymbolKind.TypeParameter
    }
}

func lspDiagnostic(text: Rope, diag: Diagnostic, encoding: Encoding): LspDiagnostic {
    let range = lspRange(text, diag.range.start, diag.range.end, encoding)
    LspDiagnostic(
        range: range,
        severity: lspSeverity(diag.severity),
        source: "cjls",
        message: StringOrMarkupContent.AsString(diag.message)
    )
}

func lspSeverity(severity: DiagnosticSeverity): LspDiagnosticSeverity {
    match (severity) {
        case DiagnosticSeverity.Error => LspDiagnosticSeverity.Error
    }
}
