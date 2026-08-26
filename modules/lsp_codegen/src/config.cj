package lsp_codegen

import cjtoml.*
import std.fs.*
import stdx.serialization.serialization.*
import stdxx.*

struct Config {
    let outputDir: Path

    Config(let srcDir!: Path, let outputPackage!: String) {
        var outputDirVal = srcDir
        // skip root package name
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
            => ConfigException(
                "cannot tell the root package of `${subPackage}`")
        }

        Config(srcDir: srcDir.resolveAgainst(cfgDir), outputPackage: "${rootPackage}.${subPackage}")
    }
}

/**
 * A path field that may legitimately be absent.
 *
 * cjpm spells "unset" as an empty string — `modules/cjls/cjpm.toml` ships `target-dir = ""` — so a
 * blank value has to mean the same thing as a missing key, or it resolves to a directory named "".
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
    ConfigFile(let srcDir!: ?Path, let outputSubpackage!: String) {}

    public static func deserialize(dm: DataModel): ConfigFile {
        let dms = dm.asStructOrThrow()
        let general = dms.get("general").asStructOrThrow()

        let srcDir = optionalPathField(general, "src-dir")

        ConfigFile(
            srcDir: srcDir,
            outputSubpackage: general.get("output-subpackage").asStringOrThrow()
        )
    }

    public func serialize(): DataModel {
        let general = DataModelStruct()
            .addFieldIfSome("src-dir", srcDir.map {it: Path => it.toString()})
            .add(field("output-subpackage", outputSubpackage))

        DataModelStruct().add(Field("general", general))
    }
}

private struct CjpmManifest <: Serializable<CjpmManifest> {
    CjpmManifest(let name!: String, let srcDir!: ?Path) {}

    public static func deserialize(dm: DataModel): CjpmManifest {
        let dms = dm.asStructOrThrow()
        let pkg = dms.get("package").asStructOrThrow()

        let srcDir = optionalPathField(pkg, "src-dir")

        CjpmManifest(
            name: pkg.get("name").asStringOrThrow(),
            srcDir: srcDir
        )
    }

    public func serialize(): DataModel {
        throw UnsupportedException("CjpmManifest serialization is not supported.")
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
