macro package cjls.macros

import std.ast.*

public macro LspHandle(input: Tokens): Tokens {
    setItem("handleDecl", input)
    input
}
