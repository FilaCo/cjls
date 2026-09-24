package lsp_codegen

import std.ast.*
import std.collection.*
import std.sort.*
import stdx.serialization.serialization.*
import stdxx.*

/**
 * A Cangjie type a metaModel type resolves to.
 */
enum TypeIr <: ToString {
    /**
     * Anything spelled by its name alone - a base type, or a type we or somebody else declares.
     */
    | Named(String)
    | ArrayOf(TypeIr)
    | MapOf(TypeIr, TypeIr)
    | NullableOf(TypeIr)

    public func toString(): String {
        match (this) {
            case Named(name) => name
            case ArrayOf(element) => "Array<${element}>"
            case MapOf(key, value) => "HashMap<${key}, ${value}>"
            case NullableOf(inner) => "Nullable<${inner}>"
        }
    }
}

extend TypeIr <: ToTokens {
    public func toTokens(): Tokens {
        cangjieLex(toString())
    }
}

/**
 * An `or` of the metaModel that is more than `T | null`, declared as an untagged enum with one
 * variant per member.
 */
struct UnionIr {
    UnionIr(let doc: DocIr, let ident!: String, let variants!: Array<UnionVariantIr>) {}
}

/**
 * An enum constructor is in scope throughout its package, unqualified - a variant named after its
 * payload, `HoverOptions(HoverOptions)`, would make `HoverOptions` a constructor everywhere and the
 * struct no type anywhere. Qualifying the payload with the package does not get past it.
 */
const VARIANT_PREFIX = "As"

/**
 * A tuple member has one payload per item - the derive reads and writes it as an array of that length.
 */
struct UnionVariantIr {
    UnionVariantIr(let ident!: String, let payloads!: Array<TypeIr>) {}
}

/**
 * The metaModel's anonymous `{ ... }` type, declared as a struct named after where it appears.
 */
struct LiteralIr {
    LiteralIr(let ident!: String, let literal!: StructureLiteral) {}
}

/**
 * A property as it reaches a struct through `extends` or `mixins`, together with where it is
 * declared: a literal among its types is named after that place, not after every struct inheriting
 * it, or each of them would declare a type of its own for the same value.
 */
struct DeclaredProperty {
    DeclaredProperty(let declaredBy!: String, let property!: Property) {}
}

/**
 * Turns metaModel types into Cangjie ones, and collects the declarations that has to invent along
 * the way: a named enum for every distinct union, a struct for every literal.
 */
class TypeResolver {
    private let structures = HashMap<String, Structure>()
    private let aliases = HashMap<String, TypeAlias>()

    /**
     * An alias whose definition is exactly a union names it, keyed by the union's canonical key.
     */
    private let unionAliases = HashMap<String, TypeAlias>()

    /**
     * Enums of ours with a `None` variant of their own: `TextDocumentSyncKind.None`.
     */
    private let noneVariantHolders = HashSet<String>()

    private let unionIdents = HashMap<String, String>()
    private let unionList = ArrayList<UnionIr>()
    private let literalList = ArrayList<LiteralIr>()

    /**
     * What each literal in `literalList` is made of, to tell the same literal met again from another
     * one after the same name.
     */
    private let literalShapes = HashMap<String, String>()

    TypeResolver(mm: MetaModel, private let cfg: Config) {
        for (structure in mm.structures) {
            structures.add(structure.name, structure)
        }
        for (enumeration in mm.enumerations) {
            let closed = !(enumeration.supportsCustomValues ?? false)
            if (closed && (enumeration.values |> any {it: EnumerationEntry => it.name.toAsciiPascalCase() == "None"})) {
                if (let Some(ident) <- cfg.typeMap.bind(enumeration.name).typeNameOf(enumeration.name)) {
                    noneVariantHolders.add(ident)
                }
            }
        }
        for (alias in mm.typeAliases) {
            aliases.add(alias.name, alias)
            if (let Or(items) <- alias.typeAliasType) {
                let members = nonNullMembers(items)
                // the first alias names the union, the ones after it alias that name: `Declaration = Definition`
                if (members.size > 1 && !unionAliases.contains(unionKeyOf(members))) {
                    unionAliases.add(unionKeyOf(members), alias)
                }
            }
        }
    }

    /**
     * Every union met so far, in the order it was first met.
     */
    prop unions: Array<UnionIr> {
        get() {
            unionList.toArray()
        }
    }

    prop literals: Array<LiteralIr> {
        get() {
            literalList.toArray()
        }
    }

    /**
     * @param context names a literal met inside `t` - `SemanticTokensOptionsRange` for the literal
     *        type of `SemanticTokensOptions.range`.
     */
    func resolve(t: Type, context!: String): TypeIr {
        match (t) {
            case Base(base) => baseType(base)
            case Reference(name) => Named(referenceTo(name))
            case Array(element) => ArrayOf(resolve(element, context: context))
            case Map(key, value) => MapOf(mapKeyType(key), resolve(value, context: context))
            case Or(items) => resolveOr(items, context)
            case Literal(literal) => Named(declareLiteral(literal, context))
            case And(_) | Tuple(_) | StringLiteral(_) | IntegerLiteral(_) | BooleanLiteral(_) =>
                throw IllegalStateException("`${context}`: ${kindOf(t)} is only supported as a union member or a tag")
        }
    }

    /**
     * A bare `None` of type `?T` is ambiguous when `T` has a `None` of its own: both constructors
     * are in scope, and both fit.
     */
    func hasOwnNone(t: TypeIr): Bool {
        match (t) {
            case Named(name) => noneVariantHolders.contains(name)
            case _ => false
        }
    }

    /**
     * The fields `structure` has on the wire: `extends` first, then `mixins`, then its own - a
     * property redeclared further down replaces the inherited one in place.
     */
    func flattenedProperties(structure: Structure): Array<DeclaredProperty> {
        let flattened = ArrayList<DeclaredProperty>()
        let bases = (structure.extends ?? []).concat(structure.mixins ?? [])
        for (base in bases) {
            let baseName = match (base) {
                case Reference(name) => name
                case _ => throw IllegalStateException("`${structure.name}` extends something other than a structure")
            }
            let baseStructure = structures.get(baseName).getOrThrow {
                => IllegalStateException("`${structure.name}` extends unknown structure `${baseName}`")
            }
            for (property in flattenedProperties(baseStructure)) {
                addOrReplace(flattened, property)
            }
        }
        let declaredBy = cfg.typeMap.bind(structure.name).typeNameOf(structure.name) ?? structure.name
        for (property in structure.properties) {
            addOrReplace(flattened, DeclaredProperty(declaredBy: declaredBy, property: property))
        }

        flattened.toArray()
    }

    private func referenceTo(lspName: String): String {
        cfg.typeMap.bind(lspName).typeNameOf(lspName).getOrThrow {
            => IllegalStateException("`${lspName}` is skipped by the config, yet something refers to it")
        }
    }

    private func baseType(base: BaseTypes): TypeIr {
        match (base) {
            case Uri => Named(referenceTo("URI"))
            case DocumentUri => Named(referenceTo("DocumentUri"))
            case Integer => Named("Int32")
            case UInteger => Named("UInt32")
            case Decimal => Named("Float64")
            case RegExp | String => Named("String")
            case Boolean => Named("Bool")
            case Null => throw IllegalStateException("`null` is only supported as a union member")
        }
    }

    private func mapKeyType(key: MapKeyType): TypeIr {
        match (key) {
            case Base(MapKeyName.Uri) => Named(referenceTo("URI"))
            case Base(MapKeyName.DocumentUri) => Named(referenceTo("DocumentUri"))
            case Base(MapKeyName.String) => Named("String")
            case Base(MapKeyName.Integer) => Named("Int32")
            case Reference(name) => Named(referenceTo(name))
        }
    }

    /**
     * `T | null` is `Nullable<T>` - unless `T` already holds `null` among its own values, the way
     * `LSPAny` does.
     */
    private func resolveOr(items: Array<Type>, context: String): TypeIr {
        let members = nonNullMembers(items)
        let inner = if (members.size == 1) {
            resolve(members[0], context: context)
        } else {
            Named(declareUnion(members, context))
        }

        if (members.size == items.size || holdsNull(members)) {
            inner
        } else {
            NullableOf(inner)
        }
    }

    private func holdsNull(members: Array<Type>): Bool {
        if (members.size != 1) {
            return false
        }
        let aliasType = match (members[0]) {
            case Reference(name) => aliases.get(name)?.typeAliasType
            case _ => None<Type>
        }

        match (aliasType) {
            case Some(Or(items)) => nonNullMembers(items).size != items.size
            case _ => false
        }
    }

    private func declareUnion(members: Array<Type>, context: String): String {
        // a literal is declared where it appears, so a union holding one belongs to that place too
        let literalCount = members |> filter {it: Type => isLiteral(it)} |> count
        if (literalCount > 1) {
            // each would be named `context`, the second one lost to the first
            throw IllegalStateException("`${context}`: a union of more than one literal has no names for them")
        }
        if (literalCount == 1 && unionAliases.contains(unionKeyOf(members))) {
            // the literal would take the alias's own name, which the union needs
            throw IllegalStateException("`${context}`: an alias of a union holding a literal has no name for it")
        }
        let key = if (literalCount == 1) {
            "${unionKeyOf(members)}@${context}"
        } else {
            unionKeyOf(members)
        }
        if (let Some(ident) <- unionIdents.get(key)) {
            return ident
        }

        let alias = unionAliases.get(key)
        let lspName = match (alias) {
            case Some(a) => a.name
            case None => String.join(members.map {it: Type => memberName(it, context)}, delimiter: "Or")
        }
        let ident = referenceTo(lspName)
        unionIdents.add(key, ident)

        if (let Owned(declared) <- cfg.typeMap.bind(lspName)) {
            let variants = narrowestFirst(members).map {
                member: Type => UnionVariantIr(ident: VARIANT_PREFIX + memberName(member, context),
                    payloads: payloadsOf(member, context))
            }
            let doc = match (alias) {
                case Some(a) => resolveDoc(a)
                case None => DocIr()
            }
            unionList.add(UnionIr(doc, ident: declared, variants: variants))
        }

        ident
    }

    private func payloadsOf(member: Type, context: String): Array<TypeIr> {
        match (member) {
            case Tuple(items) => items.map {it: Type => resolve(it, context: context)}
            case _ => [resolve(member, context: context)]
        }
    }

    /**
     * An untagged union takes the first variant that reads, and a struct reads from any object that
     * has its required keys. The one requiring more keys goes first, so the one requiring a subset
     * of them does not answer for it.
     */
    private func narrowestFirst(members: Array<Type>): Array<Type> {
        // an insertion sort, for being stable: members requiring as many keys keep the metaModel's order
        let ordered = ArrayList<(Type, Int64)>()
        for (member in members) {
            let count = requiredKeyCount(member)
            var at = ordered.size
            while (at > 0 && ordered[at - 1][1] < count) {
                at--
            }
            ordered.add((member, count), at: at)
        }

        ordered.toArray().map {it: (Type, Int64) => it[0]}
    }

    private func requiredKeyCount(t: Type): Int64 {
        let name = match (t) {
            case Reference(name) => name
            case _ => return 0
        }
        if (let Some(structure) <- structures.get(name)) {
            return flattenedProperties(structure) |> filter {it: DeclaredProperty => !(it.property.optional ?? false)} |> count
        }
        if (let Some(alias) <- aliases.get(name)) {
            return requiredKeyCount(alias.typeAliasType)
        }

        0
    }

    /**
     * How a member reads inside a union's name, and as the name of its variant.
     */
    private func memberName(t: Type, context: String): String {
        match (t) {
            case Base(base) => match (base) {
                case Uri => "URI"
                case DocumentUri => "DocumentUri"
                case Integer => "Integer"
                case UInteger => "UInteger"
                case Decimal => "Decimal"
                case RegExp => "RegExp"
                case String => "String"
                case Boolean => "Boolean"
                case Null => "Null"
            }
            case Reference(name) => name
            case Array(element) => pluralOf(memberName(element, context))
            case Literal(literal) => declareLiteral(literal, context)
            case Tuple(items) where items.size == 2 && canonicalOf(items[0]) == canonicalOf(items[1]) =>
                "${memberName(items[0], context)}Pair"
            case _ => throw IllegalStateException("`${context}`: a union member of ${kindOf(t)} has no name")
        }
    }

    private func declareLiteral(literal: StructureLiteral, context: String): String {
        let shape = literalShapeOf(literal)
        match (literalShapes.get(context)) {
            case Some(declared) where declared == shape => return context
            case Some(_) => throw IllegalStateException("`${context}` names two different literals")
            case None => ()
        }
        literalShapes.add(context, shape)
        literalList.add(LiteralIr(ident: context, literal: literal))

        context
    }
}

private func addOrReplace(properties: ArrayList<DeclaredProperty>, property: DeclaredProperty): Unit {
    for (i in 0..properties.size) {
        if (properties[i].property.name == property.property.name) {
            properties[i] = property
            return
        }
    }
    properties.add(property)
}

private func isLiteral(t: Type): Bool {
    match (t) {
        case Literal(_) => true
        case _ => false
    }
}

private func nonNullMembers(items: Array<Type>): Array<Type> {
    items.filter {
        it: Type => match (it) {
            case Base(Null) => false
            case _ => true
        }
    }
}

/**
 * The same members in any order are the same union.
 */
private func unionKeyOf(members: Array<Type>): String {
    let canonical = members.map {it: Type => canonicalOf(it)}
    sort(canonical)

    String.join(canonical, delimiter: " | ")
}

private func canonicalOf(t: Type): String {
    match (t) {
        case Base(base) => base.serialize().asStringOrThrow()
        case Reference(name) => name
        case Array(element) => "${canonicalOf(element)}[]"
        case Map(key, value) =>
            let keyName = match (key) {
                case Base(name) => name.serialize().asStringOrThrow()
                case Reference(name) => name
            }
            "{${keyName}: ${canonicalOf(value)}}"
        case Or(items) => "(${unionKeyOf(items)})"
        case And(items) => "(${String.join(items.map {it: Type => canonicalOf(it)}, delimiter: " & ")})"
        case Tuple(items) => "[${String.join(items.map {it: Type => canonicalOf(it)}, delimiter: ", ")}]"
        case Literal(_) => "{...}"
        case StringLiteral(value) => "'${value}'"
        case IntegerLiteral(value) => "${value}"
        case BooleanLiteral(value) => "${value}"
    }
}

private func literalShapeOf(literal: StructureLiteral): String {
    let properties = literal.properties.map {
        it: Property => "${it.name}${if (it.optional ?? false) { "?" } else { "" }}: ${canonicalOf(it.propertyType)}"
    }

    "{${String.join(properties, delimiter: "; ")}}"
}

private func kindOf(t: Type): String {
    match (t) {
        case Base(_) => "a base type"
        case Reference(_) => "a reference"
        case Array(_) => "an array"
        case Map(_, _) => "a map"
        case And(_) => "an `and`"
        case Or(_) => "an `or`"
        case Tuple(_) => "a tuple"
        case Literal(_) => "a literal"
        case StringLiteral(_) => "a string literal"
        case IntegerLiteral(_) => "an integer literal"
        case BooleanLiteral(_) => "a boolean literal"
    }
}

/**
 * `Location` -> `Locations`, `SymbolInformation` stays regular: an English plural is not the point,
 * a name that reads as "several of these" is.
 */
func pluralOf(name: String): String {
    if (name.endsWith("s") || name.endsWith("x") || name.endsWith("sh") || name.endsWith("ch")) {
        return "${name}es"
    }
    if (name.size >= 2 && name.endsWith("y") && !"aeiou".contains(name[name.size - 2..name.size - 1])) {
        return "${name[..name.size - 1]}ies"
    }

    "${name}s"
}
