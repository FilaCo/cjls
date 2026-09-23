package lsp_codegen

import std.collection.{ArrayList, HashMap}
import stdx.serialization.serialization.*
import stdxx.*

enum TypeBinding {
    /**
     * We declare it, under this identifier.
     */
    | Owned(String)

    /**
     * Declared elsewhere. A `public type <lspName> = <target>` is emitted for it and references
     * keep using the metaModel name, so generated signatures still read like the specification.
     */
    | Aliased(String)

    /**
     * Declared elsewhere. References resolve straight to the target and no alias is emitted.
     */
    | Extern(String)

    /**
     * Neither declared nor referred to - the metaModel entry is dropped outright.
     */
    | Skipped

    /**
     * The identifier a reference to `lspName` resolves to, or `None` when the entry is dropped.
     */
    func typeNameOf(lspName: String): ?String {
        match (this) {
            case Owned(ident) => ident
            case Aliased(_) => lspName
            case Extern(target) => target
            case Skipped => None
        }
    }
}

struct TypeMap <: Serializable<TypeMap> {
    TypeMap(let entries!: HashMap<String, TypeBinding> = HashMap<String, TypeBinding>()) {}

    func bind(lspName: String): TypeBinding {
        entries.get(lspName) ?? TypeBinding.Owned(lspName)
    }

    /**
     * `(lspName, target)` of every aliased entry
     */
    func aliases(): Array<(String, String)> {
        let found = ArrayList<(String, String)>()
        for ((lspName, binding) in entries) {
            if (let Aliased(target) <- binding) {
                found.add((lspName, target))
            }
        }

        found.toArray()
    }

    /**
     * @throws DataModelException - if an entry is not a table, or sets other than exactly one of the
     * mutually exclusive keys.
     */
    public static func deserialize(dm: DataModel): TypeMap {
        let dms = match (dm) {
            case dms: DataModelStruct => dms
            case _: DataModelNull => return TypeMap()
            case _ => throw DataModelException("Unexpected `DataModel`, expected `DataModelStruct` or `DataModelNull`")
        }

        let entries = HashMap<String, TypeBinding>()
        for (field in dms.getFields()) {
            entries.add(field.getName(), bindingOf(field.getName(), field.getData()))
        }

        TypeMap(entries: entries)
    }

    public func serialize(): DataModel {
        throw UnsupportedException()
    }
}

private func bindingOf(lspName: String, dm: DataModel): TypeBinding {
    let entry = dm.asStructOrThrow()

    let fields = entry.getFields()
    if (fields.isEmpty()) {
        throw DataModelException("`types.${lspName}` sets none of `rename`, `alias`, `extern`, `skip`")
    }

    if (fields.size > 1) {
        throw DataModelException("`types.${lspName}` sets more than one of `rename`, `alias`, `extern`, `skip`")
    }

    // fields.size == 1
    let given = fields[0]
    let key = given.getName()
    let data = given.getData()
    match (key) {
        case "rename" => Owned(targetOf(lspName, key, data))
        case "alias" => Aliased(targetOf(lspName, key, data))
        case "extern" => Extern(targetOf(lspName, key, data))
        case "skip" where data.asBoolOrThrow() => Skipped
        case _ => throw DataModelException("unknown field \"${key}\"")
    }
}

/**
 * The Cangjie identifier a binding points at. A blank one would emit `public type LSPAny = ` and
 * only surface as a syntax error in the generated file, far from the config line that caused it.
 */
private func targetOf(lspName: String, key: String, dm: DataModel): String {
    let target = dm.asStringOrThrow().trimAscii()
    if (target.isEmpty()) {
        throw DataModelException("`types.${lspName}.${key}` must not be empty")
    }

    target
}
