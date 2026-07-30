macro package cjls.macros

import std.ast.*

public macro LspNotification(attrs: Tokens, input: Tokens): Tokens {
    let parsedAttrs = LspNotificationAttrs.parse(attrs)

    let (ident, genericParam, genericConstraint) = match (parseDecl(input)) {
        case cd: ClassDecl =>
            let (genericParam, genericConstraint) = cd.getGenericFragments()
            (cd.identifier, genericParam, genericConstraint)
        case sd: StructDecl =>
            let (genericParam, genericConstraint) = sd.getGenericFragments()
            (sd.identifier, genericParam, genericConstraint)
        case ed: EnumDecl =>
            let (genericParam, genericConstraint) = ed.getGenericFragments()
            (ed.identifier, genericParam, genericConstraint)
        case _ =>
            diagReport(ERROR, input, "unsupported decl", "use class, struct or enum instead")
            return input
    }

    let messages = getChildMessages("LspHandle")
    if (messages.isEmpty()) {
        diagReport(ERROR, input, "@LspNotification: no @LspHandle method found in ${ident.value}",
            "add a @LspHandle-annotated static func to the struct")
        return input
    }

    let handleTokens = messages[0].getTokens("handleDecl")
    if (let fd: FuncDecl <- parseDecl(handleTokens)) {
        let handleCall = buildHandleCall(ident, fd)
        return input + extendLspNotification(genericParam, ident, parsedAttrs.params, genericConstraint,
            parsedAttrs.method, handleCall)
    }

    diagReport(ERROR, handleTokens, "invalid @LspHandle declaration",
        "@LspHandle declaration has to be a func declaration")
    return input
}

private struct LspNotificationAttrs {
    private LspNotificationAttrs(let method: Expr, let params: Tokens) {}
    static func parse(attrs: Tokens): LspNotificationAttrs {
        let args = lexAttrs(attrs)
        var method = None<Expr>
        var params = quote(Unit)
        for (arg in args) {
            if (arg.colon.kind == ILLEGAL) {
                continue
            }
            match (arg.identifier.value) {
                case "method" => method = arg.expr
                case "params" => params = arg.expr.toTokens()
                case _ => continue
            }
        }
        if (let Some(method) <- method) {
            return LspNotificationAttrs(method, params)
        }
        diagReport(ERROR, attrs, "not enough arguments", "add \"method: \"<yourmethodname>\"\" argument")
        throw Exception()
    }
}

/**
 * Build the body of the generated `handle(params: P, ctx: GlobalContext)`:
 * a call to the user's @LspHandle static method, mapping each user parameter
 * by name - "params" gets the interface param, anything else gets ctx.<name>.
 */
private func buildHandleCall(outerDeclIdent: Token, fd: FuncDecl): Tokens {
    var callArgs = Tokens()
    for (p in fd.funcParams) {
        let pName = p.identifier
        if (pName.value == "params") {
            callArgs += quote(params, )
        } else {
            callArgs += quote(ctx.$pName, )
        }
    }
    let funcName = fd.identifier
    quote($outerDeclIdent.$funcName($callArgs))
}

private func extendLspNotification(genericParam: Tokens, ident: Token, paramTy: Tokens, genericConstraint: Tokens,
    methodExpr: Expr, handleCall: Tokens): Tokens {
    quote(
        extend $genericParam $ident $genericParam <: LspNotification<$paramTy> $genericConstraint {
            
            public static prop METHOD: String {
                get() {
                    $methodExpr
                }
            }

            
            public static func handle(params: $paramTy, ctx: GlobalContext): Unit {
                $handleCall
            }
        }
    )
}
