package loupe

import std.collection.*
import ginkgo.{SyntaxElement, TextRange}
import cjsyntax.{CjSyntaxNode, SyntaxKind}
import loupe.vfs.FileId
import loupe.db.RootDatabase
import loupe.syntax.parse

public enum StructureKind <: Equatable<StructureKind> & ToString {
    | Class
    | Interface
    | Struct
    | Enum
    | EnumConstructor
    | Extension
    | Function
    | Method
    | Macro
    | Main
    | Constructor
    | Finalizer
    | Property
    | Variable
    | Field
    | Constant
    | TypeAlias

    public operator func ==(other: StructureKind): Bool {
        toString() == other.toString()
    }

    public operator func !=(other: StructureKind): Bool {
        !(this == other)
    }

    public func toString(): String {
        match (this) {
            case Class => "Class"
            case Interface => "Interface"
            case Struct => "Struct"
            case Enum => "Enum"
            case EnumConstructor => "EnumConstructor"
            case Extension => "Extension"
            case Function => "Function"
            case Method => "Method"
            case Macro => "Macro"
            case Main => "Main"
            case Constructor => "Constructor"
            case Finalizer => "Finalizer"
            case Property => "Property"
            case Variable => "Variable"
            case Field => "Field"
            case Constant => "Constant"
            case TypeAlias => "TypeAlias"
        }
    }
}

/**
 * One declaration of a file's outline. `range` is the whole of it, doc comment included;
 * `selectionRange`, inside it, is its name.
 */
public class StructureNode {
    public StructureNode(
        public let name: String,
        public let kind: StructureKind,
        public let range: TextRange,
        public let selectionRange: TextRange,
        public let children: Array<StructureNode>
    ) {}
}

/**
 * The declarations of a file, nested as they are: what a type declares is under it, what a
 * function body declares is not in the outline. Empty for a file the database does not know.
 */
public func fileStructure(db: RootDatabase, fileId: FileId): Array<StructureNode> {
    let file = db.sourceFile(fileId) ?? return []
    structureOf(parse(db, file).syntaxNode(), false)
}

/**
 * The declarations among `container`'s children; `inType` when it is a type's body.
 */
private func structureOf(container: CjSyntaxNode, inType: Bool): Array<StructureNode> {
    let nodes = ArrayList<StructureNode>()
    for (child in container.children()) {
        nodes.add(all: declarationsOf(child, inType))
    }
    nodes.toArray()
}

private func declarationsOf(node: CjSyntaxNode, inType: Bool): Array<StructureNode> {
    match (node.kind) {
        case SyntaxKind.ClassDecl => named(node, StructureKind.Class, bodyOf(node))
        case SyntaxKind.InterfaceDecl => named(node, StructureKind.Interface, bodyOf(node))
        case SyntaxKind.StructDecl => named(node, StructureKind.Struct, bodyOf(node))
        case SyntaxKind.EnumDecl => named(node, StructureKind.Enum, bodyOf(node))
        case SyntaxKind.EnumCtor => named(node, StructureKind.EnumConstructor, [])
        case SyntaxKind.ExtendDecl => extension(node)
        case SyntaxKind.FuncDecl =>
            named(node, if (inType) { StructureKind.Method } else { StructureKind.Function }, [])
        case SyntaxKind.MacroDecl => named(node, StructureKind.Macro, [])
        case SyntaxKind.PrimaryInitDecl => named(node, StructureKind.Constructor, [])
        case SyntaxKind.PropDecl => named(node, StructureKind.Property, [])
        case SyntaxKind.TypeAliasDecl => named(node, StructureKind.TypeAlias, [])
        case SyntaxKind.MainDecl => byKeyword(node, "main", StructureKind.Main, SyntaxKind.MainKw)
        case SyntaxKind.InitDecl => byKeyword(node, "init", StructureKind.Constructor, SyntaxKind.InitKw)
        case SyntaxKind.FinalizerDecl => byKeyword(node, "~init", StructureKind.Finalizer, SyntaxKind.InitKw)
        case SyntaxKind.VarDecl => variables(node, inType)
        // a macro call or a `foreign` block declares what is inside it
        case SyntaxKind.MacroExpandDecl | SyntaxKind.ForeignBlock => structureOf(node, inType)
        case _ => []
    }
}

/**
 * A declaration named by its `Name`; none if it has none yet, as while it is being typed.
 */
private func named(node: CjSyntaxNode, kind: StructureKind, children: Array<StructureNode>): Array<StructureNode> {
    match (childOf(node, SyntaxKind.Name)) {
        case Some(name) => [StructureNode(name.text(), kind, node.textRange, name.textRange, children)]
        case None => []
    }
}

/**
 * `main`, `init`, `~init`: named by a keyword, which is what is selected.
 */
private func byKeyword(node: CjSyntaxNode, name: String, kind: StructureKind, keyword: SyntaxKind): Array<StructureNode> {
    for (element in node.childrenWithTokens()) {
        match (element) {
            case SyntaxElement.Token(token) where token.kind == keyword =>
                return [StructureNode(name, kind, node.textRange, token.textRange, [])]
            case _ => ()
        }
    }
    []
}

/**
 * Named by the type it extends, as written.
 */
private func extension(node: CjSyntaxNode): Array<StructureNode> {
    for (child in node.children()) {
        match (child.kind) {
            case SyntaxKind.Modifiers | SyntaxKind.Annotation | SyntaxKind.TypeParamList => ()
            case SyntaxKind.DeclBody => return []
            case _ => return [StructureNode(child.text(), StructureKind.Extension, node.textRange, child.textRange,
                    bodyOf(node))]
        }
    }
    []
}

/**
 * One per name a `let`, `var` or `const` binds: `let (a, b) = t` declares two.
 */
private func variables(node: CjSyntaxNode, inType: Bool): Array<StructureNode> {
    let isConst = match (childOf(node, SyntaxKind.Modifiers)) {
        case Some(modifiers) => modifiers.text().contains("const")
        case None => false
    }
    let kind = if (isConst) {
        StructureKind.Constant
    } else if (inType) {
        StructureKind.Field
    } else {
        StructureKind.Variable
    }
    if (let Some(name) <- childOf(node, SyntaxKind.Name)) {
        return [StructureNode(name.text(), kind, node.textRange, name.textRange, [])]
    }
    // a pattern: the first child node that binds, before the type and the initializer
    let pattern = node.children().filter {child => child.kind.toString().endsWith("Pat")}.next() ?? return []
    let names = pattern.descendants()
        .filter {descendant => descendant.kind == SyntaxKind.Name}
        .map {name => StructureNode(name.text(), kind, node.textRange, name.textRange, [])}
    collectArray(names)
}

private func bodyOf(node: CjSyntaxNode): Array<StructureNode> {
    for (child in node.children()) {
        match (child.kind) {
            case SyntaxKind.DeclBody | SyntaxKind.EnumBody => return structureOf(child, true)
            case _ => ()
        }
    }
    []
}

private func childOf(node: CjSyntaxNode, kind: SyntaxKind): ?CjSyntaxNode {
    node.children().filter {child => child.kind == kind}.next()
}
