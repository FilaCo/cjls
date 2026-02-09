import std.env.getVariable
import std.fs.{exists, Directory, SymbolicLink, removeIfExists, Path}

main(args: Array<String>) {
    let stage = args[0]
    match (stage) {
        case "pre-build" => onPreBuild()
        case "pre-clean" => onPostClean()
        case _ => ()
    }
}

func onPreBuild(): Unit {
    let localStdxPath = getLocalStdxPath()
    if (exists(localStdxPath)) {
        return
    }

    if (!exists(localStdxPath.parent)) {
        Directory.create(localStdxPath.parent, recursive: true)
    }

    const CANGJIE_STDX_PATH_ENV = "CANGJIE_STDX_PATH"
    let globalStdxPath = getVariable(CANGJIE_STDX_PATH_ENV).getOrThrow {=> CangjieStdxPathEnvNotFoundException()}
    SymbolicLink.create(localStdxPath, to: Path(globalStdxPath))
}

class CangjieStdxPathEnvNotFoundException <: Exception {}

func onPostClean(): Unit {
    let localStdxPath = getLocalStdxPath()
    removeIfExists(localStdxPath.parent, recursive: true)
}

func getLocalStdxPath(): Path {
    const THIRD_PARTY_STDX_PATH = "third_party/stdx"
    Path(THIRD_PARTY_STDX_PATH)
}
