package loupe

import std.collection.*
import ginkgo.TextRange
import cjsyntax.CjSyntaxToken
import cjsyntax.ast.{Decl, ExtendDecl, Name, Pattern, SourceFile, VarDecl}
import loupe.vfs.FileId
import loupe.db.AnalysisDatabase
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
public func fileStructure(db: AnalysisDatabase, fileId: FileId): Array<StructureNode> {
    let file = db.sourceFile(fileId) ?? return []
    let root = SourceFile.cast(parse(db, file).syntaxNode()) ?? return []
    structureOf(root.decls(), false)
}

/**
 * The outline of `decls`; `inType` when they are a type's members.
 */
private func structureOf(decls: Iterator<Decl>, inType: Bool): Array<StructureNode> {
    let nodes = ArrayList<StructureNode>()
    for (decl in decls) {
        nodes.add(all: declarationsOf(decl, inType))
    }
    nodes.toArray()
}

private func declarationsOf(decl: Decl, inType: Bool): Array<StructureNode> {
    match (decl) {
        case Decl.AsClassDecl(it) => named(decl, it.name(), StructureKind.Class, members(it.declBody()?.decls()))
        case Decl.AsInterfaceDecl(it) =>
            named(decl, it.name(), StructureKind.Interface, members(it.declBody()?.decls()))
        case Decl.AsStructDecl(it) => named(decl, it.name(), StructureKind.Struct, members(it.declBody()?.decls()))
        case Decl.AsEnumDecl(it) => named(decl, it.name(), StructureKind.Enum, members(it.enumBody()?.decls()))
        case Decl.AsEnumCtor(it) => named(decl, it.name(), StructureKind.EnumConstructor, [])
        case Decl.AsExtendDecl(it) => extension(it)
        case Decl.AsFuncDecl(it) =>
            named(decl, it.name(), if (inType) { StructureKind.Method } else { StructureKind.Function }, [])
        case Decl.AsMacroDecl(it) => named(decl, it.name(), StructureKind.Macro, [])
        case Decl.AsPrimaryInitDecl(it) => named(decl, it.name(), StructureKind.Constructor, [])
        case Decl.AsPropDecl(it) => named(decl, it.name(), StructureKind.Property, [])
        case Decl.AsTypeAliasDecl(it) => named(decl, it.name(), StructureKind.TypeAlias, [])
        case Decl.AsMainDecl(it) => byKeyword(decl, "main", StructureKind.Main, it.mainToken())
        case Decl.AsInitDecl(it) => byKeyword(decl, "init", StructureKind.Constructor, it.initToken())
        case Decl.AsFinalizerDecl(it) => byKeyword(decl, "~init", StructureKind.Finalizer, it.initToken())
        case Decl.AsVarDecl(it) => variables(it, inType)
        // a macro call or a `foreign` block declares what is inside it
        case Decl.AsMacroExpandDecl(it) => match (it.decl()) {
            case Some(inner) => declarationsOf(inner, inType)
            case None => []
        }
        case Decl.AsForeignBlock(it) => structureOf(it.decls(), inType)
    }
}

/**
 * A declaration named by its `Name`; none if it has none yet, as while it is being typed.
 */
private func named(decl: Decl, name: ?Name, kind: StructureKind, children: Array<StructureNode>): Array<StructureNode> {
    match (name) {
        case Some(name) => [StructureNode(name.syntax.text(), kind, decl.syntax.textRange, name.syntax.textRange,
                children)]
        case None => []
    }
}

/**
 * `main`, `init`, `~init`: named by a keyword, which is what is selected.
 */
private func byKeyword(decl: Decl, name: String, kind: StructureKind, keyword: ?CjSyntaxToken): Array<StructureNode> {
    match (keyword) {
        case Some(token) => [StructureNode(name, kind, decl.syntax.textRange, token.textRange, [])]
        case None => []
    }
}

/**
 * Named by the type it extends, as written.
 */
private func extension(decl: ExtendDecl): Array<StructureNode> {
    let ty = decl.ty() ?? return []
    [StructureNode(ty.syntax.text(), StructureKind.Extension, decl.syntax.textRange, ty.syntax.textRange,
        members(decl.declBody()?.decls()))]
}

/**
 * One per name a `let`, `var` or `const` binds: `let (a, b) = t` declares two.
 */
private func variables(decl: VarDecl, inType: Bool): Array<StructureNode> {
    let isConst = match (decl.modifiers()) {
        case Some(modifiers) => modifiers.constToken().isSome()
        case None => false
    }
    let kind = if (isConst) {
        StructureKind.Constant
    } else if (inType) {
        StructureKind.Field
    } else {
        StructureKind.Variable
    }
    let names = ArrayList<Name>()
    match ((decl.name(), decl.pattern())) {
        case (Some(name), _) => names.add(name)
        case (None, Some(pattern)) => collectBindings(pattern, names)
        case _ => ()
    }
    names.toArray().map {name => StructureNode(name.syntax.text(), kind, decl.syntax.textRange, name.syntax.textRange, [])}
}

/**
 * The names `pattern` binds, in the order they are written.
 */
private func collectBindings(pattern: Pattern, names: ArrayList<Name>): Unit {
    match (pattern) {
        case Pattern.AsBindPat(it) => if (let Some(name) <- it.name()) {
            names.add(name)
        }
        case Pattern.AsTypePat(it) => if (let Some(name) <- it.name()) {
            names.add(name)
        }
        case Pattern.AsTuplePat(it) => for (inner in it.patterns()) {
            collectBindings(inner, names)
        }
        case Pattern.AsEnumPat(it) => for (inner in it.patterns()) {
            collectBindings(inner, names)
        }
        case Pattern.AsWildcardPat(_) | Pattern.AsLiteralPat(_) => ()
    }
}

/**
 * A type's members; none while it has no body.
 */
private func members(decls: ?Iterator<Decl>): Array<StructureNode> {
    structureOf(decls ?? return [], true)
}
