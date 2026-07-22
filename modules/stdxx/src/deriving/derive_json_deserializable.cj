macro package stdxx.deriving

import std.ast.*

func deriveJsonDeserializable(decl: Decl): Tokens {
    match (decl) {
        case sd: StructDecl => deriveJsonDeserializableWithStructDecl(sd)
        case _ =>
            diagReport(ERROR, decl.toTokens(), "unable to derive JsonDeserializable with ${decl.identifier.value}",
                "supports only `struct` declarations")
            decl.toTokens()
    }
}

private func deriveJsonDeserializableWithStructDecl(sd: StructDecl): Tokens {
    match (primaryCtorOf(sd)) {
        case Some(pcd) => deriveJsonDeserializableWithStructDecl(sd, pcd)
        case None =>
            diagReport(ERROR, sd.toTokens(), "unable to derive JsonDeserializable with ${sd.identifier.value}",
                "declare a primary constructor")
            sd.toTokens()
    }
}

private func deriveJsonDeserializableWithStructDecl(sd: StructDecl, pcd: PrimaryCtorDecl): Tokens {
    var varDecls = Tokens()
    var varCases = Tokens()
    var pcdCallArgs = Tokens()
    for (param in pcd.funcParams.filter {p => p.isMemberParam()}) {
        let ident = param.identifier
        let ty = param.paramType
        let hasDefault = param.assign.kind != ILLEGAL

        if (hasDefault) {
            varDecls += quote(var $(ident): $(ty) = $(param.expr);)
            varCases += quote(case $(ident.value) => $(ident) = r.readValue();)
            pcdCallArgs += if (param.not.kind != ILLEGAL) {
                quote($(ident): $(ident),)
            } else {
                quote($(ident),)
            }
        } else {
            varDecls += quote(var $(ident) = None<$(ty)>;)
            varCases += quote(case $(ident.value) => $(ident) = r.readValue();)
            pcdCallArgs += if (param.not.kind != ILLEGAL) {
                quote($(ident): $(ident).getOrThrow(),)
            } else {
                quote($(ident).getOrThrow(),)
            }
        }
    }

    let (genericParam, genericConstraint) = genericFragments(sd)
    let pcdCallExpr = quote($(sd.identifier)$(genericParam)($pcdCallArgs))
    extendJsonDeserializable(genericParam, sd.identifier, genericConstraint, varDecls, varCases, pcdCallExpr)
}

private func extendJsonDeserializable(genericParam: Tokens, ident: Token, genericConstraint: Tokens, varDecls: Tokens,
    varCases: Tokens, pcdCallExpr: Tokens): Tokens {
    quote(
        extend $genericParam $ident $genericParam <: JsonDeserializable<$ident $genericParam> $genericConstraint {
            public static func fromJson(r: JsonReader): $ident $genericParam {
                while (let Some(tag) <- r.peek()) {
                    match (tag) {
                        case BeginObject =>
                            $varDecls
                            r.startObject()
                            while (r.peek() != EndObject) {
                                match (r.readName()) {
                                    $varCases
                                    case _ => r.skip()
                                }
                            }
                            r.endObject()
                            return $pcdCallExpr
                        case _ => throw IllegalStateException()
                    }
                }
                throw IllegalStateException()
            }
        }
    )
}
