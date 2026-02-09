macro package calca.macros

import std.ast.*

public macro Database(input: Tokens): Tokens {
    quote(Float64.parse("123.321"))
}
