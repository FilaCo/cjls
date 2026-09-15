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
    let decls = bodyDeclsOf(decl) ?? return None

    for (member in decls) {
        if (let primaryCtor: PrimaryCtorDecl <- member) {
            return primaryCtor
        }
    }

    None
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
    for (token in tokens) {
        if (token.kind == TokenKind.IDENTIFIER) {
            return token
        }
    }

    None
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

func joined(parts: ArrayList<String>, separator: String): String {
    let sb = StringBuilder()
    for ((i, part) in parts |> enumerate) {
        if (i > 0) {
            sb.append(separator)
        }
        sb.append(part)
    }

    sb.toString()
}

/**
 * What a declaration opens with once its modifiers are out of the way - `public let x!: T` says
 * `let` just as `let x!: T` does.
 */
func headTokenOf(tokens: Tokens): ?Token {
    for (token in tokens) {
        if (!isModifier(token)) {
            return token
        }
    }

    None
}

private func isModifier(token: Token): Bool {
    match (token.value) {
        case "public" | "protected" | "private" | "internal" | "open" | "sealed" | "abstract" | "static" | "override"
            | "redef" | "mut" | "unsafe" | "foreign" | "const" | "operator" | "common" | "specific" => true
        case _ => false
    }
}
