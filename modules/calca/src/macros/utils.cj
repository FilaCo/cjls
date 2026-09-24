macro package calca.macros

import std.ast.*
import std.collection.*

func modifiersOf(modifiers: ArrayList<Modifier>): Tokens {
    var tokens = Tokens()
    for (modifier in modifiers) {
        tokens += modifier.toTokens()
    }
    tokens
}

/**
 * `` `type` `` -> `type`: backquotes escape an identifier in the source and are no part of its name.
 */
func stripBackquotes(ident: String): String {
    if (ident.size >= 2 && ident.startsWith("`") && ident.endsWith("`")) {
        ident[1..ident.size - 1]
    } else {
        ident
    }
}

func capitalized(name: String): String {
    if (name.isEmpty()) {
        name
    } else {
        name[0..1].toAsciiUpper() + name[1..]
    }
}
