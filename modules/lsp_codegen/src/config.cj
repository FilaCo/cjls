package lsp_codegen

import std.fs.Path
import stdx.serialization.serialization.*
import stdxx.*

struct Config <: Serializable<Config> {
    let outputDir: Path

    Config(let srcDir!: Path, let outputPackage!: String) {
        var outputDirVal = srcDir
        // skip root package name
        for (s in outputPackage.split(".")[1..]) {
            outputDirVal = outputDirVal.join(s)
        }
        outputDir = outputDirVal
    }

    public static func deserialize(dm: DataModel): Config {
        let dms = dm.asStructOrThrow()
        let general = dms.get("general").asStructOrThrow()

        Config(
            srcDir: Path(general.get("src-dir").asStringOrThrow()).normalize(),
            outputPackage: general.get("output-package").asStringOrThrow()
        )
    }

    public func serialize(): DataModel {
        let general = DataModelStruct()
            .add(field("src-dir", srcDir.toString()))
            .add(field("output-package", outputPackage))

        DataModelStruct().addFieldIfSome("general", general)
    }
}
