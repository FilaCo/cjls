macro package stdxx.deriving

import std.ast.*
import std.collection.*

/**
 * The declarations inside the body of a `struct`/`class`, `None` for anything else.
 */
func bodyDeclsOf(decl: Decl): ?ArrayList<Decl> {
    if (let sd: StructDecl <- decl) {
        return sd.body.decls
    }
    if (let cd: ClassDecl <- decl) {
        return cd.body.decls
    }

    None
}

func primaryCtorOf(decl: Decl): ?PrimaryCtorDecl {
    (bodyDeclsOf(decl) ?? return None).filterMap {member => member as PrimaryCtorDecl}.first
}

/**
 * The `<T, U>` fragment of a generic declaration, empty for a non-generic one.
 */
func typeArgsOf(decl: Decl): Tokens {
    if (decl.isGenericDecl) {
        decl.genericParam.toTokens()
    } else {
        Tokens()
    }
}

/**
 * The first identifier of a token sequence - the name of whatever it declares.
 */
func identOf(tokens: Tokens): ?Token {
    tokens |> filter {token: Token => token.kind == TokenKind.IDENTIFIER} |> first
}

/**
 * `` `type` `` -> `type`. Identifiers keep their backquotes all the way through the AST,
 * they are an escaping detail of the source, never part of the name.
 */
func stripBackquotes(ident: String): String {
    if (ident.size >= 2 && ident.startsWith("`") && ident.endsWith("`")) {
        ident[1..ident.size - 1]
    } else {
        ident
    }
}

/**
 * The pieces with a comma between each two, as in an argument list or a pattern.
 */
func commaSeparated(parts: Array<Tokens>): Tokens {
    var joined = Tokens()
    for ((i, part) in parts |> enumerate) {
        if (i > 0) {
            joined += Tokens(Token(TokenKind.COMMA))
        }
        joined += part
    }

    joined
}

/**
 * The first entry whose key an earlier one already took.
 */
func firstDuplicate(entries: Array<(String, Token)>): ?(String, Token) {
    let taken = HashSet<String>()
    for ((key, token) in entries) {
        if (!taken.add(key)) {
            return (key, token)
        }
    }

    None
}

/**
 * What a declaration opens with once its modifiers are out of the way - `public let x!: T` says
 * `let` just as `let x!: T` does.
 */
func headTokenOf(tokens: Tokens): ?Token {
    tokens |> filter {token: Token => !isModifier(token)} |> first
}

private func isModifier(token: Token): Bool {
    match (token.value) {
        case "public" | "protected" | "private" | "internal" | "open" | "sealed" | "abstract" | "static" | "override"
            | "redef" | "mut" | "unsafe" | "foreign" | "const" | "operator" | "common" | "specific" => true
        case _ => false
    }
}

func report(ident: Token, message: String, hint: String): Tokens {
    diagReport(DiagReportLevel.ERROR, ident.toTokens(), message, hint)

    Tokens()
}

func report(decl: Decl, message: String, hint: String): Tokens {
    report(decl.identifier, message, hint)
}
