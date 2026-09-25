package lsp_codegen

import std.ast.*
import std.collection.{ArrayList, HashSet}
import std.fs.Path

struct CjFile {
    CjFile(let path: Path, let contents: String) {}
}

func generateCjFiles(cfg: Config, mm: MetaModel): Array<CjFile> {
    let resolver = TypeResolver(mm, cfg)
    let files = ArrayList<CjFile>(mm.enumerations.filterMap {it: Enumeration => resolveEnum(cfg, it)}.map {
        enumIr: EnumIr => cjFileOf(cfg, mm, enumIr.ident) {emitter => emitter.emitEnum(enumIr)}
    })

    let structs = ArrayList<StructIr>(mm.structures.filterMap {it: Structure => resolveStruct(cfg, resolver, it)})
    let aliasLines = resolveAliases(cfg, resolver, mm)
    let messages = resolveMessages(resolver, mm)
    // a literal may hold further literals and unions of its own, met only once it is resolved
    var resolvedLiterals = 0
    while (resolvedLiterals < resolver.literals.size) {
        structs.add(resolveLiteral(resolver, resolver.literals[resolvedLiterals]))
        resolvedLiterals++
    }

    files.add(all: structs.toArray().map {
        structIr: StructIr => cjFileOf(cfg, mm, structIr.ident) {emitter => emitter.emitStruct(structIr)}
    })
    files.add(all: resolver.unions.map {
        unionIr: UnionIr => cjFileOf(cfg, mm, unionIr.ident) {emitter => emitter.emitUnion(unionIr)}
    })
    files.add(all: messages.map {
        messageIr: MessageIr => cjFileOf(cfg, mm, messageIr.ident) {emitter => emitter.emitMessage(messageIr)}
    })
    let configuredAliases = cfg.typeMap.aliases()
    if (!configuredAliases.isEmpty() || !aliasLines.isEmpty()) {
        files.add(cjFileOf(cfg, mm, "aliases") {emitter => emitter.emitAliases(configuredAliases, aliasLines)})
    }
    files.add(cjFileOf(cfg, mm, "spec") {emitter => emitter.emitSpecDeclarations()})
    checkUniquePaths(files)

    files.toArray()
}

/**
 * Two declarations whose names only differ in case would land in one file, the second overwriting
 * the first without a word.
 */
private func checkUniquePaths(files: ArrayList<CjFile>): Unit {
    let taken = HashSet<String>()
    for (file in files) {
        if (!taken.add(file.path.toString())) {
            throw IllegalStateException("two declarations generate `${file.path}`")
        }
    }
}

private func cjFileOf(cfg: Config, mm: MetaModel, ident: String, body: (CjEmitter) -> Unit): CjFile {
    let contents = emittedBy {
        emitter =>
            emitter.emitPreamble(mm.metaData.version, Token(PACKAGE_IDENTIFIER, cfg.outputPackage), cfg.imports)
            body(emitter)
    }

    CjFile(cfg.outputDir.join("${ident.toAsciiLowerSnakeCase()}.cj"), contents)
}

/**
 * `public type <name> = <target>` for every alias we own that is not a union - a union alias names
 * the enum declared for it instead.
 */
private func resolveAliases(cfg: Config, resolver: TypeResolver, mm: MetaModel): Array<(DocIr, String, TypeIr)> {
    let lines = ArrayList<(DocIr, String, TypeIr)>()
    for (alias in mm.typeAliases) {
        let target = resolver.resolve(alias.typeAliasType, context: alias.name)
        if (let Owned(ident) <- cfg.typeMap.bind(alias.name)) {
            if (target.toString() != ident) {
                lines.add((resolveDoc(alias), ident, target))
            }
        }
    }

    lines.toArray()
}

private let SPEC_DECLARATIONS = """
/**
 * A message of the protocol. A value of it names the message where its handler is registered -
 * `.route(InitializeRequestSpec(), handleInitialize)` - and brings its method and types along.
 */
public interface LspMessageSpec {
    static prop METHOD: String
    static prop DIRECTION: MessageDirection

    prop method: String
}

/**
 * A request the client sends, which the server answers. `P` is `Unit` for a request that takes no
 * params, `R` for one answered with a bare `null` - `shutdown`.
 */
public interface LspInboundRequest<P, R> <: LspMessageSpec {
    /**
     * Absent params read as `null`.
     *
     * @throws RpcException - `INVALID_PARAMS`, if the params do not read as a `P`
     */
    func decodeParams(params: ?ArrayOrObject): P

    func encodeResult(result: R): DataModel
}

/**
 * A request the server sends, which the client answers.
 */
public interface LspOutboundRequest<P, R> <: LspMessageSpec {}

/**
 * A notification the client sends. `P` is `Unit` for one that takes no params - `exit`.
 */
public interface LspInboundNotification<P> <: LspMessageSpec {
    /**
     * Absent params read as `null`.
     *
     * @throws RpcException - `INVALID_PARAMS`, if the params do not read as a `P`
     */
    func decodeParams(params: ?ArrayOrObject): P
}

/**
 * A notification the server sends.
 */
public interface LspOutboundNotification<P> <: LspMessageSpec {}

/**
 * Absent params read as `null`, so a `P` that allows for none - a struct of optional fields only -
 * takes them without a word.
 *
 * @throws RpcException - `INVALID_PARAMS`, if the params do not read as a `P`
 */
func decodeMessageParams<P>(params: ?ArrayOrObject): P where P <: Serializable<P> {
    let dm = match (params) {
        case Some(given) => given.serialize()
        case None => DataModelNull()
    }
    try {
        P.deserialize(dm)
    } catch (e: Exception) {
        throw RpcException(ErrorCode.INVALID_PARAMS, e.message)
    }
}
"""

extend CjEmitter {
    func emitAliases(configured: Array<(String, String)>, generated: Array<(DocIr, String, TypeIr)>): Unit {
        for ((lspName, target) in configured) {
            let aliasIdent = escapedIdent(lspName)
            let targetType = Token(IDENTIFIER, target)
            emitln(quote(public type $aliasIdent = $targetType))
        }
        for ((doc, ident, target) in generated) {
            let aliasIdent = escapedIdent(ident)
            nl()
            emitDoc(doc)
            // verbatim: cjfmt leaves the spaces `Tokens` puts around `<` and `>` in a type alias
            emitln("public type ${aliasIdent.value} = ${target}")
        }
    }

    func emitSpecDeclarations(): Unit {
        emit(DocComment(lines: ["Indicates in which direction a message is sent in the protocol."]))
        emitln(
            quote(
public enum MessageDirection {
    | ClientToServer
    | ServerToClient
    | Both
}
        ))
        nl()
        // verbatim: `quote` has no way to spell a doc comment, and these carry the contract
        emit(SPEC_DECLARATIONS)
    }

    func emitPreamble(version: String, outputPackage: Token, imports: Collection<String>): Unit {
        emitln(DocComment(lines: ["Generated by lsp_codegen from metaModel.json ${version}."]))
        emitln(quote(package $outputPackage))
        for (importContent in imports) {
            emitln(quote(import $(cangjieLex(importContent))))
        }
        nl()
    }
}
