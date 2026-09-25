macro package cjls.macros

import std.ast.*

/**
 * Makes a function of what it takes from the server, params last, routable, by adding an overload
 * of the same name that takes the context instead and extracts the arguments from it:
 *
 * ```cangjie
 * @LspHandler[readonly]
 * func handleHover(snap: ServerSnapshot, cancellation: CancellationToken, params: HoverParams): Nullable<Hover>
 * // adds
 * func handleHover(context: ReadOnlyContext<HoverParams>): Nullable<Hover> {
 *     handleHover(ServerSnapshot.from(context), CancellationToken.from(context), context.params)
 * }
 * ```
 *
 * The params come last. `@LspHandler` runs on the read loop with a `Context`, `@LspHandler[readonly]` on
 * a thread of its own with a `ReadOnlyContext`; an argument the context cannot give fails to
 * compile inside the added overload.
 */
public macro LspHandler(input: Tokens): Tokens {
    withContextOverload(input, quote(Context))
}

public macro LspHandler(attrs: Tokens, input: Tokens): Tokens {
    if (attrs.size != 1 || attrs[0].value != "readonly") {
        diagReport(DiagReportLevel.ERROR, attrs, "`@LspHandler` takes no option but `readonly`", "write `@LspHandler[readonly]`, or `@LspHandler` for a handler that runs on the read loop")
        return input
    }
    withContextOverload(input, quote(ReadOnlyContext))
}

private func withContextOverload(input: Tokens, context: Tokens): Tokens {
    let handler = match (parseDecl(input)) {
        case fd: FuncDecl => fd
        case _ =>
            diagReport(DiagReportLevel.ERROR, input, "`@LspHandler` goes on a function", "")
            return input
    }
    let params = handler.funcParams
    if (handler.isGenericDecl || params.isEmpty()) {
        diagReport(DiagReportLevel.ERROR, input, "a handler is not generic, and takes at least its params", "")
        return input
    }
    for (param in params where isNamed(param)) {
        diagReport(DiagReportLevel.ERROR, param.toTokens(), "a handler's parameters are positional", "")
        return input
    }

    let name = handler.identifier
    var args = Tokens()
    for (i in 0..params.size - 1) {
        let extracted = params[i].paramType.toTokens()
        args += quote($extracted.from(context), )
    }
    args += quote(context.params)

    var modifiers = Tokens()
    for (modifier in handler.modifiers) {
        modifiers += modifier.toTokens()
    }
    let paramsType = params[params.size - 1].paramType.toTokens()
    let returnType = try {
        let declared = handler.declType.toTokens()
        quote(: $declared)
    } catch (_: ASTException) {
        Tokens()
    }

    input + quote(
        $modifiers func $name(context: $context<$paramsType>) $returnType {
            $name($args)
        }
    )
}

private func isNamed(param: FuncParam): Bool {
    for (token in param.toTokens() where token.kind == TokenKind.NOT) {
        return true
    }
    false
}
