macro package calca.macros

import std.ast.*
import std.collection.*

/**
 * Makes a function of the database and at most one more argument a query, as salsa's
 * `#[salsa::tracked]` is: its value is remembered per argument, along with everything it read, and
 * computed again only once something it read has changed.
 *
 * ```cangjie
 * @Tracked
 * public func lineCount(db: Db, file: SourceFile): Int64 {
 *     file.text(db).split("\n").size
 * }
 * ```
 *
 * The database comes first, typed as the database interface the body needs; the argument is
 * `Hashable` and `Equatable`, an `@Input` for one. A value computed again that equals the one
 * remembered does not make what read it run again, so the result is `Equatable` too, unless
 * `@Tracked[noEq]` says to count every computation as a change.
 */
public macro Tracked(input: Tokens): Tokens {
    tracked(input, quote({old, new => old == new}))
}

public macro Tracked(attrs: Tokens, input: Tokens): Tokens {
    if (attrs.size != 1 || attrs[0].value != "noEq") {
        diagReport(DiagReportLevel.ERROR, attrs, "`@Tracked` takes no option but `noEq`", "")
        return input
    }
    tracked(input, quote({_, _ => false}))
}

private func tracked(input: Tokens, equal: Tokens): Tokens {
    let decl = match (parseDecl(input)) {
        case fd: FuncDecl => fd
        case _ =>
            diagReport(DiagReportLevel.ERROR, input, "`@Tracked` goes on a function", "")
            return input
    }
    let params = decl.funcParams
    if (decl.isGenericDecl) {
        diagReport(DiagReportLevel.ERROR, input, "a tracked function is not generic", "")
        return input
    }
    if (params.isEmpty() || params.size > 2) {
        diagReport(DiagReportLevel.ERROR, input, "a tracked function takes the database, and at most one argument more", "")
        return input
    }
    for (param in params where param.not.kind == TokenKind.NOT) {
        diagReport(DiagReportLevel.ERROR, param.toTokens(), "a tracked function's parameters are positional", "")
        return input
    }
    let returnType = try {
        decl.declType.toTokens()
    } catch (_: ASTException) {
        diagReport(DiagReportLevel.ERROR, input, "a tracked function declares its return type", "")
        return input
    }

    let name = decl.identifier
    let holder = Token(TokenKind.IDENTIFIER, "CalcaTracked_" + stripBackquotes(name.value))
    let nameLiteral = Token(TokenKind.STRING_LITERAL, stripBackquotes(name.value))
    let db = params[0].identifier
    let dbType = params[0].paramType.toTokens()
    let (keyType, keyParam, keyArg, signature) = if (params.size == 2) {
        let key = params[1].identifier
        let keyType = params[1].paramType.toTokens()
        (keyType, quote($key: $keyType), quote($key), quote($db: $dbType, $key: $keyType))
    } else {
        (quote(Unit), quote(_: Unit), quote(()), quote($db: $dbType))
    }
    let modifiers = modifiersOf(decl.modifiers)
    let body = decl.block.toTokens()

    quote(
        $modifiers func $name($signature): $returnType {
            $holder.FUNCTION.fetch($db, $keyArg, $holder.execute)
        }

        private struct $holder {
            static let FUNCTION = TrackedFunction<$dbType, $keyType, $returnType>($nameLiteral, $equal)

            static func execute($db: $dbType, $keyParam): $returnType $body
        }
    )
}
