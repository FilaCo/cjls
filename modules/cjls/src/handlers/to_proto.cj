package cjls.handlers

import std.collection.ArrayList
import rope.{Encoding, LineColumn, Rope}
import loupe.{HighlightedRange, HighlightModifier, HighlightModifiers, HighlightTag, Severity, StructureKind, StructureNode}
import loupe.Diagnostic as LoupeDiagnostic
import cjls.lsp_types.*
import cjls.lsp_types.Range as LspRange

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

func diagnostic(text: Rope, diagnostic: LoupeDiagnostic, encoding: Encoding): Diagnostic {
    Diagnostic(
        range: lspRange(text, diagnostic.range.start, diagnostic.range.end, encoding),
        severity: diagnosticSeverity(diagnostic.severity),
        source: "cjls",
        message: StringOrMarkupContent.AsString(diagnostic.message)
    )
}

func diagnosticSeverity(severity: Severity): DiagnosticSeverity {
    match (severity) {
        case Severity.Error => DiagnosticSeverity.Error
    }
}

/**
 * The token types the server sends, LSP's own only, so every theme knows them (D19); a token's
 * type is its index here.
 */
let TOKEN_TYPES = [SemanticTokenTypes.KEYWORD, SemanticTokenTypes.COMMENT, SemanticTokenTypes.STRING,
    SemanticTokenTypes.NUMBER, SemanticTokenTypes.OPERATOR, SemanticTokenTypes.DECORATOR,
    SemanticTokenTypes.MACRO, SemanticTokenTypes.TYPE, SemanticTokenTypes.CLASS,
    SemanticTokenTypes.INTERFACE, SemanticTokenTypes.STRUCT, SemanticTokenTypes.ENUM,
    SemanticTokenTypes.ENUM_MEMBER, SemanticTokenTypes.TYPE_PARAMETER, SemanticTokenTypes.FUNCTION,
    SemanticTokenTypes.METHOD, SemanticTokenTypes.PROPERTY, SemanticTokenTypes.VARIABLE,
    SemanticTokenTypes.PARAMETER]

/**
 * The modifiers, LSP's own too; a token's modifiers are bits by their index here.
 */
let TOKEN_MODIFIERS = [(SemanticTokenModifiers.DECLARATION, HighlightModifier.Declaration),
    (SemanticTokenModifiers.DOCUMENTATION, HighlightModifier.Documentation),
    (SemanticTokenModifiers.READONLY, HighlightModifier.Readonly),
    (SemanticTokenModifiers.STATIC, HighlightModifier.Static),
    (SemanticTokenModifiers.DEPRECATED, HighlightModifier.Deprecated),
    (SemanticTokenModifiers.DEFAULT_LIBRARY, HighlightModifier.DefaultLibrary)]

func semanticTokensLegend(): SemanticTokensLegend {
    SemanticTokensLegend(tokenTypes: TOKEN_TYPES.map {it => it.value},
        tokenModifiers: TOKEN_MODIFIERS.map {it => it[0].value})
}

/**
 * LSP has no type for a constructor, a field or a constant: they go as a method, a property and a
 * `readonly` variable, as LSP's own documentation has it.
 */
func tokenType(tag: HighlightTag): SemanticTokenTypes {
    match (tag) {
        case HighlightTag.Keyword => SemanticTokenTypes.KEYWORD
        case HighlightTag.Comment => SemanticTokenTypes.COMMENT
        case HighlightTag.StringLiteral => SemanticTokenTypes.STRING
        case HighlightTag.NumberLiteral => SemanticTokenTypes.NUMBER
        case HighlightTag.Operator => SemanticTokenTypes.OPERATOR
        case HighlightTag.BuiltinAnnotation => SemanticTokenTypes.DECORATOR
        case HighlightTag.MacroCall => SemanticTokenTypes.MACRO
        case HighlightTag.BuiltinType | HighlightTag.TypeName => SemanticTokenTypes.TYPE
        case HighlightTag.TypeParameter => SemanticTokenTypes.TYPE_PARAMETER
        case HighlightTag.Parameter => SemanticTokenTypes.PARAMETER
        case HighlightTag.Declared(kind) => match (kind) {
            case StructureKind.Class => SemanticTokenTypes.CLASS
            case StructureKind.Interface => SemanticTokenTypes.INTERFACE
            case StructureKind.Struct => SemanticTokenTypes.STRUCT
            case StructureKind.Enum => SemanticTokenTypes.ENUM
            case StructureKind.EnumConstructor => SemanticTokenTypes.ENUM_MEMBER
            case StructureKind.Extension | StructureKind.TypeAlias => SemanticTokenTypes.TYPE
            case StructureKind.Function | StructureKind.Main => SemanticTokenTypes.FUNCTION
            case StructureKind.Method | StructureKind.Constructor | StructureKind.Finalizer =>
                SemanticTokenTypes.METHOD
            case StructureKind.Macro => SemanticTokenTypes.MACRO
            case StructureKind.Property | StructureKind.Field => SemanticTokenTypes.PROPERTY
            case StructureKind.Variable | StructureKind.Constant => SemanticTokenTypes.VARIABLE
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
func semanticTokens(text: Rope, tokens: Array<HighlightedRange>, encoding: Encoding, multiline: Bool): SemanticTokens {
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
    SemanticTokens(data: data.toArray())
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
