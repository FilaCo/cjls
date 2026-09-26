package cjls.handlers

import rope.{Encoding, Rope}
import loupe.*
import cjls.lsp_types as lsp

/**
 * `start..end`, byte offsets into `text`, as the client counts: lines and columns of `encoding`.
 * `text` has to be the one the offsets were computed on, the snapshot's.
 */
func lspRange(text: Rope, start: Int64, end: Int64, encoding: Encoding): lsp.Range {
    lsp.Range(start: lspPosition(text, start, encoding), end: lspPosition(text, end, encoding))
}

func lspPosition(text: Rope, offset: Int64, encoding: Encoding): lsp.Position {
    let position = text.positionOf(offset, encoding)
    lsp.Position(line: UInt32(position.line), character: UInt32(position.column))
}

func documentSymbol(text: Rope, node: StructureNode, encoding: Encoding): lsp.DocumentSymbol {
    lsp.DocumentSymbol(
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
func symbolKind(kind: StructureKind): lsp.SymbolKind {
    match (kind) {
        case StructureKind.Class => lsp.SymbolKind.Class
        case StructureKind.Interface => lsp.SymbolKind.Interface
        case StructureKind.Struct => lsp.SymbolKind.Struct
        case StructureKind.Enum => lsp.SymbolKind.Enum
        case StructureKind.EnumConstructor => lsp.SymbolKind.EnumMember
        case StructureKind.Extension => lsp.SymbolKind.Object
        case StructureKind.Function | StructureKind.Macro | StructureKind.Main => lsp.SymbolKind.Function
        case StructureKind.Method | StructureKind.Finalizer => lsp.SymbolKind.Method
        case StructureKind.Constructor => lsp.SymbolKind.Constructor
        case StructureKind.Property => lsp.SymbolKind.Property
        case StructureKind.Variable => lsp.SymbolKind.Variable
        case StructureKind.Field => lsp.SymbolKind.Field
        case StructureKind.Constant => lsp.SymbolKind.Constant
        case StructureKind.TypeAlias => lsp.SymbolKind.TypeParameter
    }
}

func diagnostic(text: Rope, diagnostic: Diagnostic, encoding: Encoding): lsp.Diagnostic {
    lsp.Diagnostic(
        range: lspRange(text, diagnostic.range.start, diagnostic.range.end, encoding),
        severity: diagnosticSeverity(diagnostic.severity),
        source: "cjls",
        message: lsp.StringOrMarkupContent.AsString(diagnostic.message)
    )
}

func diagnosticSeverity(severity: Severity): lsp.DiagnosticSeverity {
    match (severity) {
        case Severity.Error => lsp.DiagnosticSeverity.Error
    }
}
