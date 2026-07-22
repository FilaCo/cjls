macro package stdxx.deriving

import std.ast.*

func deriveJsonSerializable(decl: Decl): Tokens {
    match (decl) {
        case sd: StructDecl => deriveJsonSerializableWithStructDecl(sd)
        case _ =>
            diagReport(ERROR, decl.toTokens(), "unable to derive JsonSerializable with ${decl.identifier.value}",
                "supports only `struct` declarations")
            decl.toTokens()
    }
}

private func deriveJsonSerializableWithStructDecl(sd: StructDecl): Tokens {
    match (sd.getPrimaryCtor()) {
        case Some(pcd) => deriveJsonSerializableWithStructDecl(sd, pcd)
        case None =>
            diagReport(ERROR, sd.toTokens(), "unable to derive JsonSerializable with ${sd.identifier.value}",
                "declare a primary constructor")
            sd.toTokens()
    }
}

private func deriveJsonSerializableWithStructDecl(sd: StructDecl, pcd: PrimaryCtorDecl): Tokens {
    var toJsonBody = Tokens()
    for (param in pcd.funcParams.filter {p => p.isMemberParam()}) {
        let name = param.identifier
        let hasDefault = param.assign.kind != ILLEGAL
        toJsonBody += if (hasDefault) {
            // Option<T> field with default value - emit only when present, so `null` is never
            // written for a missing value.
            quote(if (let Some(v) <- $(name)) { w.writeName($(name.value)).writeValue(v) };)
        } else {
            quote(w.writeName($(name.value)).writeValue($(name));)
        }
    }
    let (genericParam, genericConstraint) = sd.getGenericFragments()
    extendJsonSerializable(genericParam, sd.identifier, genericConstraint, toJsonBody)
}

private func extendJsonSerializable(genericParam: Tokens, ident: Token, genericConstraint: Tokens, toJsonBody: Tokens): Tokens {
    quote(
        extend $genericParam $ident $genericParam $genericConstraint <: JsonSerializable {
            @Frozen
            public func toJson(w: JsonWriter): Unit {
                w.startObject()
                $toJsonBody
                w.endObject()
            }
        }
    )
}
