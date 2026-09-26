package cjls.handlers

import std.collection.ArrayList
import rope.{Encoding, LineColumn, Rope}
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

/**
 * The token types the server sends, LSP's own only, so every theme knows them (D16); a token's
 * type is its index here.
 */
let TOKEN_TYPES = [lsp.SemanticTokenTypes.KEYWORD, lsp.SemanticTokenTypes.COMMENT, lsp.SemanticTokenTypes.STRING,
    lsp.SemanticTokenTypes.NUMBER, lsp.SemanticTokenTypes.OPERATOR, lsp.SemanticTokenTypes.DECORATOR,
    lsp.SemanticTokenTypes.MACRO, lsp.SemanticTokenTypes.TYPE, lsp.SemanticTokenTypes.CLASS,
    lsp.SemanticTokenTypes.INTERFACE, lsp.SemanticTokenTypes.STRUCT, lsp.SemanticTokenTypes.ENUM,
    lsp.SemanticTokenTypes.ENUM_MEMBER, lsp.SemanticTokenTypes.TYPE_PARAMETER, lsp.SemanticTokenTypes.FUNCTION,
    lsp.SemanticTokenTypes.METHOD, lsp.SemanticTokenTypes.PROPERTY, lsp.SemanticTokenTypes.VARIABLE,
    lsp.SemanticTokenTypes.PARAMETER]

/**
 * The modifiers, LSP's own too; a token's modifiers are bits by their index here.
 */
let TOKEN_MODIFIERS = [(lsp.SemanticTokenModifiers.DECLARATION, HighlightModifier.Declaration),
    (lsp.SemanticTokenModifiers.DOCUMENTATION, HighlightModifier.Documentation),
    (lsp.SemanticTokenModifiers.READONLY, HighlightModifier.Readonly),
    (lsp.SemanticTokenModifiers.STATIC, HighlightModifier.Static),
    (lsp.SemanticTokenModifiers.DEPRECATED, HighlightModifier.Deprecated),
    (lsp.SemanticTokenModifiers.DEFAULT_LIBRARY, HighlightModifier.DefaultLibrary)]

func semanticTokensLegend(): lsp.SemanticTokensLegend {
    lsp.SemanticTokensLegend(tokenTypes: TOKEN_TYPES.map {it => it.value},
        tokenModifiers: TOKEN_MODIFIERS.map {it => it[0].value})
}

/**
 * LSP has no type for a constructor, a field or a constant: they go as a method, a property and a
 * `readonly` variable, as LSP's own documentation has it.
 */
func tokenType(tag: HighlightTag): lsp.SemanticTokenTypes {
    match (tag) {
        case HighlightTag.Keyword => lsp.SemanticTokenTypes.KEYWORD
        case HighlightTag.Comment => lsp.SemanticTokenTypes.COMMENT
        case HighlightTag.StringLiteral => lsp.SemanticTokenTypes.STRING
        case HighlightTag.NumberLiteral => lsp.SemanticTokenTypes.NUMBER
        case HighlightTag.Operator => lsp.SemanticTokenTypes.OPERATOR
        case HighlightTag.BuiltinAnnotation => lsp.SemanticTokenTypes.DECORATOR
        case HighlightTag.MacroCall => lsp.SemanticTokenTypes.MACRO
        case HighlightTag.BuiltinType | HighlightTag.TypeName => lsp.SemanticTokenTypes.TYPE
        case HighlightTag.TypeParameter => lsp.SemanticTokenTypes.TYPE_PARAMETER
        case HighlightTag.Parameter => lsp.SemanticTokenTypes.PARAMETER
        case HighlightTag.Declared(kind) => match (kind) {
            case StructureKind.Class => lsp.SemanticTokenTypes.CLASS
            case StructureKind.Interface => lsp.SemanticTokenTypes.INTERFACE
            case StructureKind.Struct => lsp.SemanticTokenTypes.STRUCT
            case StructureKind.Enum => lsp.SemanticTokenTypes.ENUM
            case StructureKind.EnumConstructor => lsp.SemanticTokenTypes.ENUM_MEMBER
            case StructureKind.Extension | StructureKind.TypeAlias => lsp.SemanticTokenTypes.TYPE
            case StructureKind.Function | StructureKind.Main => lsp.SemanticTokenTypes.FUNCTION
            case StructureKind.Method | StructureKind.Constructor | StructureKind.Finalizer =>
                lsp.SemanticTokenTypes.METHOD
            case StructureKind.Macro => lsp.SemanticTokenTypes.MACRO
            case StructureKind.Property | StructureKind.Field => lsp.SemanticTokenTypes.PROPERTY
            case StructureKind.Variable | StructureKind.Constant => lsp.SemanticTokenTypes.VARIABLE
        }
    }
}

func tokenTypeIndex(tag: HighlightTag): UInt32 {
    let tokenKind = tokenType(tag)
    var index = 0
    while (TOKEN_TYPES[index].value != tokenKind.value) {
        index++
    }
    UInt32(index)
}

func tokenModifierBits(modifiers: HighlightModifiers): UInt32 {
    var bits: UInt32 = 0
    for (i in 0..TOKEN_MODIFIERS.size where modifiers.contains(TOKEN_MODIFIERS[i][1])) {
        bits |= 1 << UInt32(i)
    }
    bits
}

/**
 * `tokens`, in the order of `text`, packed as LSP has them: five numbers each, the line and the
 * start relative to the token before, columns of `encoding`. A token over several lines is cut at
 * each line's end, unless the client takes it whole (`multiline`).
 */
func semanticTokens(text: Rope, tokens: Array<HighlightedRange>, encoding: Encoding, multiline: Bool): lsp.SemanticTokens {
    let data = SemanticTokensData()
    for (token in tokens) {
        let tokenKind = tokenTypeIndex(token.tag)
        let modifiers = tokenModifierBits(token.modifiers)
        let start = text.positionOf(token.range.start, encoding)
        let end = text.positionOf(token.range.end, encoding)
        if (start.line == end.line) {
            data.add(start, end.column - start.column, tokenKind, modifiers)
        } else if (multiline) {
            let length = text.summaryBefore(token.range.end).measure(encoding) -
                text.summaryBefore(token.range.start).measure(encoding)
            data.add(start, length, tokenKind, modifiers)
        } else {
            for (line in start.line..=end.line) {
                let from = if (line == start.line) {
                    start.column
                } else {
                    0
                }
                let to = if (line == end.line) {
                    end.column
                } else {
                    text.positionOf(text.lineEnd(line), encoding).column
                }
                if (to > from) {
                    data.add(LineColumn(line, from), to - from, tokenKind, modifiers)
                }
            }
        }
    }
    lsp.SemanticTokens(data: data.toArray())
}

class SemanticTokensData {
    private let data = ArrayList<UInt32>()
    private var line = 0
    private var column = 0

    /**
     * A token at `start`, after all those added before it.
     */
    func add(start: LineColumn, length: Int64, tokenKind: UInt32, modifiers: UInt32): Unit {
        let deltaLine = start.line - line
        let deltaStart = if (deltaLine == 0) {
            start.column - column
        } else {
            start.column
        }
        data.add(all: [UInt32(deltaLine), UInt32(deltaStart), UInt32(length), tokenKind, modifiers])
        line = start.line
        column = start.column
    }

    func toArray(): Array<UInt32> {
        data.toArray()
    }
}
