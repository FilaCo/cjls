macro package calca.macros

import std.ast.*
import std.collection.*

/**
 * Makes a function of the database and at most one more argument a query, as salsa's
 * `#[salsa::tracked]` is: its value is remembered per argument, along with everything it read, and
 * computed again only once something it read has changed.
 *
 * ```cangjie
 * @CalcaTracked
 * public func lineCount(db: Db, file: SourceFile): Int64 {
 *     file.text(db).split("\n").size
 * }
 * ```
 *
 * The database comes first, typed as the database interface the body needs; the argument is
 * `Hashable` and `Equatable`, an `@CalcaInput` for one. A value computed again that equals the one
 * remembered does not make what read it run again, so the result is `Equatable` too, unless
 * `@CalcaTracked[noEq]` says to count every computation as a change.
 *
 * `@CalcaTracked[lru: 128]` keeps the values of the 128 keys fetched last from one revision to the
 * next, and lets go of the others; what they read is kept, so they are verified without being
 * computed, and computed again only when fetched. For values that are large and cheap to compute
 * again (a file's tree). Options go together: `@CalcaTracked[noEq, lru: 128]`.
 */
public macro CalcaTracked(input: Tokens): Tokens {
    tracked(input, quote({old, new => old == new}), quote())
}

public macro CalcaTracked(attrs: Tokens, input: Tokens): Tokens {
    var equal = quote({old, new => old == new})
    var lru = quote()
    var i = 0
    while (i < attrs.size) {
        let option = attrs[i]
        match (option.value) {
            case "noEq" =>
                equal = quote({_, _ => false})
                i++
            // a literal has no sign, `-` is a token of its own
            case "lru" where i + 2 < attrs.size && attrs[i + 1].kind == TokenKind.COLON && attrs[i + 2].kind ==
                TokenKind.INTEGER_LITERAL =>
                let capacity = attrs[i + 2]
                lru = quote(, lru: $capacity)
                i += 3
            case "lru" =>
                diagReport(DiagReportLevel.ERROR, attrs, "`lru` takes how many values to keep: `lru: 128`", "")
                return input
            case _ =>
                diagReport(DiagReportLevel.ERROR, attrs, "`@CalcaTracked` takes no option but `noEq` and `lru: N`", "")
                return input
        }
        if (i < attrs.size) {
            if (attrs[i].kind != TokenKind.COMMA) {
                diagReport(DiagReportLevel.ERROR, attrs, "`@CalcaTracked`'s options are separated by commas", "")
                return input
            }
            i++
        }
    }
    tracked(input, equal, lru)
}

private func tracked(input: Tokens, equal: Tokens, lru: Tokens): Tokens {
    let decl = match (parseDecl(input)) {
        case fd: FuncDecl => fd
        case _ =>
            diagReport(DiagReportLevel.ERROR, input, "`@CalcaTracked` goes on a function", "")
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
            static let FUNCTION = TrackedFunction<$dbType, $keyType, $returnType>($(nameLiteral(name)), $equal $lru)

            static func execute($db: $dbType, $keyParam): $returnType $body
        }
    )
}
