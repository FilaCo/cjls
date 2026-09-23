package lsp_codegen

import std.ast.*
import std.collection.{ArrayList, HashSet}
import std.fs.Path
import std.io.{ByteBuffer, StringWriter, readToEnd}

struct CjFile {
    CjFile(let path: Path, let contents: String) {}
}

func generateCjFiles(cfg: Config, mm: MetaModel): Array<CjFile> {
    let resolver = TypeResolver(mm, cfg)
    let files = ArrayList<CjFile>(generateEnumerationFiles(cfg, mm))

    let structs = ArrayList<StructIr>(mm.structures.filterMap {it: Structure => resolveStruct(cfg, resolver, it)})
    let aliasLines = resolveAliases(cfg, resolver, mm)
    resolveMessageTypes(resolver, mm)
    // a literal may hold further literals and unions of its own, met only once it is resolved
    var resolvedLiterals = 0
    while (resolvedLiterals < resolver.literals.size) {
        structs.add(resolveLiteral(resolver, resolver.literals[resolvedLiterals]))
        resolvedLiterals++
    }

    for (structIr in structs) {
        files.add(cjFileOf(cfg, mm, structIr.ident) {emitter => emitter.emitStruct(structIr)})
    }
    for (unionIr in resolver.unions) {
        files.add(cjFileOf(cfg, mm, unionIr.ident) {emitter => emitter.emitUnion(unionIr)})
    }
    if (let Some(aliases) <- generateAliasesFile(cfg, mm, aliasLines)) {
        files.add(aliases)
    }
    files.add(generateSpecFile(cfg, mm))
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
    let byteBuffer = ByteBuffer()
    let cjEmitter = CjEmitter(byteBuffer)
    cjEmitter.preambled(mm.metaData.version, Token(PACKAGE_IDENTIFIER, cfg.outputPackage), cfg.imports) {
        => body(cjEmitter)
    }
    cjEmitter.flush()
    let contents = unsafe { String.fromUtf8(readToEnd(byteBuffer)) }

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

/**
 * The messages themselves come later, but the unions only they use belong with the rest.
 */
private func resolveMessageTypes(resolver: TypeResolver, mm: MetaModel): Unit {
    func resolveAll(owner: String, types: Array<(String, ?Type)>): Unit {
        for ((part, t) in types) {
            match (t) {
                // a request answered with nothing - `shutdown` - has `null` for its whole result
                case Some(Base(Null)) | None => ()
                case Some(some) => resolver.resolve(some, context: owner + part)
            }
        }
    }
    func paramsOf(params: ?OneOrMany<Type>): ?Type {
        match (params) {
            case Some(One(t)) => t
            case _ => None
        }
    }

    for (request in mm.requests) {
        resolveAll(request.typeName ?? request.method, [("Params", paramsOf(request.params)), ("Result", request.result),
            ("PartialResult", request.partialResult), ("ErrorData", request.errorData),
            ("RegistrationOptions", request.registrationOptions)])
    }
    for (notification in mm.notifications) {
        resolveAll(notification.typeName ?? notification.method, [("Params", paramsOf(notification.params)),
            ("RegistrationOptions", notification.registrationOptions)])
    }
}

private func generateAliasesFile(cfg: Config, mm: MetaModel, generated: Array<(DocIr, String, TypeIr)>): ?CjFile {
    let aliases = cfg.typeMap.aliases()
    if (aliases.isEmpty() && generated.isEmpty()) {
        return None
    }

    let byteBuffer = ByteBuffer()
    let cjEmitter = CjEmitter(byteBuffer)
    cjEmitter.preambled(mm.metaData.version, Token(PACKAGE_IDENTIFIER, cfg.outputPackage), cfg.imports) {
        =>
            for ((lspName, target) in aliases) {
                let aliasIdent = escapedIdent(lspName)
                let targetType = Token(IDENTIFIER, target)
                cjEmitter.emitln(quote(public type $aliasIdent = $targetType))
            }
            for ((doc, ident, target) in generated) {
                let aliasIdent = escapedIdent(ident)
                cjEmitter.nl()
                cjEmitter.emitDoc(doc)
                // verbatim: cjfmt leaves the spaces `Tokens` puts around `<` and `>` in a type alias
                cjEmitter.emitln("public type ${aliasIdent.value} = ${target}")
            }
    }
    cjEmitter.flush()
    let contents = unsafe { String.fromUtf8(readToEnd(byteBuffer)) }
    let path = cfg.outputDir.join("aliases.cj")
    CjFile(path, contents)
}

private func generateSpecFile(cfg: Config, mm: MetaModel) {
    let byteBuffer = ByteBuffer()
    let cjEmitter = CjEmitter(byteBuffer)
    cjEmitter.preambled(mm.metaData.version, Token(PACKAGE_IDENTIFIER, cfg.outputPackage), cfg.imports) {
        =>
            cjEmitter.emit(DocComment(lines: ["Indicates in which direction a message is sent in the protocol."]))
            cjEmitter.emitln(
                quote(
public enum MessageDirection {
    | ClientToServer
    | ServerToClient
    | Both
}
        ))
            cjEmitter.emitln(
                quote(
public interface LspRequestSpec<P, R> {
    static prop METHOD: String
    static prop DIRECTION: MessageDirection
}

public interface LspNotificationSpec<P> {
    static prop METHOD: String
    static prop DIRECTION: MessageDirection
}
))
    }
    cjEmitter.flush()
    let contents = unsafe { String.fromUtf8(readToEnd(byteBuffer)) }
    let path = cfg.outputDir.join("spec.cj")
    CjFile(path, contents)
}

private func generateEnumerationFiles(cfg: Config, mm: MetaModel): Array<CjFile> {
    mm.enumerations.filterMap {enumeration: Enumeration => resolveEnum(cfg, enumeration)}.map {
        enumIr: EnumIr =>
            let byteBuffer = ByteBuffer()
            let cjEmitter = CjEmitter(byteBuffer)
            cjEmitter.preambled(mm.metaData.version, Token(PACKAGE_IDENTIFIER, cfg.outputPackage), cfg.imports) {
                => cjEmitter.emitEnum(enumIr)
            }
            cjEmitter.flush()
            let contents = unsafe { String.fromUtf8(readToEnd(byteBuffer)) }
            let path = cfg.outputDir.join("${enumIr.ident.toAsciiLowerSnakeCase()}.cj")
            CjFile(path, contents)
    }
}

extend CjEmitter {
    func preambled(version: String, outputPackage: Token, imports: Collection<String>, body: () -> Unit): Unit {
        emitln(DocComment(lines: ["Generated by lsp_codegen from metaModel.json ${version}."]))
        emitln(quote(package $outputPackage))
        for (importContent in imports) {
            emitln(quote(import $(cangjieLex(importContent))))
        }
        nl()

        body()
    }
}
