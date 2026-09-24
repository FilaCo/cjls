package lsp_codegen

import std.fs.*
import stdx.serialization.serialization.*
import stdxx.serialization.*
import cjtoml.*

struct Config {
    let outputDir: Path

    Config(
        let srcDir!: Path,
        let outputPackage!: String,
        let imports!: Collection<String> = [],
        let typeMap!: TypeMap = TypeMap()
    ) {
        var outputDirVal = srcDir
        // cjpm names a subpackage `<root>.<path under src-dir>`: the root is no directory
        for (s in outputPackage.split(".")[1..]) {
            outputDirVal = outputDirVal.join(s)
        }
        outputDir = outputDirVal
    }

    static func load(cfgPath: Path): Config {
        let cfgDir = parentDirOf(cfgPath)
        let cfgFile = unmarshal<ConfigFile>(cfgPath.toString())
        let manifest = CjpmManifest.load(cfgDir)

        let subPackage = cfgFile.outputSubpackage.trimAscii()
        if (subPackage.isEmpty()) {
            throw ConfigException("`output-subpackage` must not be empty")
        }

        let srcDir = cfgFile.srcDir ?? manifest.flatMap {it: CjpmManifest => it.srcDir} ?? Path("src")
        let rootPackage = manifest.flatMap {it: CjpmManifest => it.name}.getOrThrow {
            => ConfigException("cannot tell the root package of `${subPackage}`")
        }

        Config(
            imports: cfgFile.imports,
            srcDir: srcDir.resolveAgainst(cfgDir),
            outputPackage: "${rootPackage}.${subPackage}",
            typeMap: cfgFile.typeMap,
        )
    }
}

/**
 * cjpm writes `""` for an unset `src-dir`, so a blank one falls through to the next source.
 */
private func optionalPathField(dms: DataModelStruct, key: String): ?Path {
    let raw: ?String = match (dms.get(key)) {
        case s: DataModelString => s.getValue()
        case _: DataModelNull => None
        case _ => throw DataModelException("Invalid `${key}` field type")
    }

    let value = raw.map {it: String => it.trimAscii()} ?? ""
    if (value.isEmpty()) {
        None
    } else {
        Path(value)
    }
}

/**
 * The directory a config path lives in - `Path.parent` is empty for a bare filename, and every
 * `join`/`normalize` on an empty path throws.
 */
func parentDirOf(cfgPath: Path): Path {
    let parent = cfgPath.parent
    if (parent.isEmpty()) {
        Path("./")
    } else {
        parent
    }
}

class ConfigException <: Exception {
    ConfigException(message: String) {
        super(message)
    }

    protected override func getClassName(): String {
        "ConfigException"
    }
}

private struct ConfigFile <: Serializable<ConfigFile> {
    ConfigFile(let srcDir!: ?Path, let outputSubpackage!: String, let imports!: Array<String>, let typeMap!: TypeMap) {}

    public static func deserialize(dm: DataModel): ConfigFile {
        let dms = dm.asStructOrThrow()
        let general = dms.get("general").asStructOrThrow()

        ConfigFile(
            srcDir: optionalPathField(general, "src-dir"),
            outputSubpackage: general.get("output-subpackage").asStringOrThrow(),
            imports: stringListField(general, "imports"),
            typeMap: TypeMap.deserialize(dms.get("types"))
        )
    }

    public func serialize(): DataModel {
        throw UnsupportedException()
    }
}

private func stringListField(dms: DataModelStruct, key: String): Array<String> {
    let items = match (dms.get(key)) {
        case seq: DataModelSeq => seq.getItems()
        case _: DataModelNull => return []
        case _ => throw ConfigException("`${key}` must be an array of strings")
    }

    items.map {
        it: DataModel => match (it) {
            case s: DataModelString => s.getValue()
            case _ => throw ConfigException("`${key}` must be an array of strings")
        }
    }.toArray()
}

private struct CjpmManifest <: Serializable<CjpmManifest> {
    CjpmManifest(let name!: String, let srcDir!: ?Path) {}

    public static func deserialize(dm: DataModel): CjpmManifest {
        let dms = dm.asStructOrThrow()
        let pkg = dms.get("package").asStructOrThrow()

        CjpmManifest(name: pkg.get("name").asStringOrThrow(), srcDir: optionalPathField(pkg, "src-dir"))
    }

    public func serialize(): DataModel {
        throw UnsupportedException()
    }

    static func load(cfgDir: Path): ?CjpmManifest {
        let manifestPath = cfgDir.join("cjpm.toml")
        if (!exists(manifestPath)) {
            return None
        }

        unmarshal<CjpmManifest>(manifestPath.toString())
    }
}

extend Path {
    func resolveAgainst(base: Path): Path {
        if (isAbsolute()) {
            normalize()
        } else {
            base.join(this).normalize()
        }
    }
}
