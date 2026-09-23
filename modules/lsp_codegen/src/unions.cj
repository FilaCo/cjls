package lsp_codegen

import std.ast.*
import std.collection.{ArrayList, enumerate}

extend CjEmitter {
    /**
     * Untagged: the variants are ordered narrowest first, and the first one the value reads as wins.
     */
    func emitUnion(unionIr: UnionIr): Unit {
        let unionIdent = escapedIdent(unionIr.ident)

        emitDoc(unionIr.doc)
        emitDerives([Serializable(SerializableTypeOptions())])
        emit(quote(public enum $unionIdent))
        blockln {
            => for (variant in unionIr.variants) {
                let variantIdent = escapedIdent(variant.ident)
                var payloads = Tokens()
                for ((i, payload) in variant.payloads |> enumerate) {
                    if (i > 0) {
                        payloads += Tokens(Token(COMMA))
                    }
                    payloads += payload.toTokens()
                }
                emitln(quote(| $variantIdent($payloads)))
            }
        }
    }
}
