macro package stdxx.deriving

import std.ast.*

func deriveJson(decl: Decl): Tokens {
    deriveJsonDeserializable(decl) + deriveJsonSerializable(decl)
}
