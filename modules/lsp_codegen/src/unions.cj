package lsp_codegen

import std.ast.*

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
                let payloads = joined(variant.payloads.map {it: TypeIr => it.toTokens()}) ?? Tokens()
                emitln(quote(| $variantIdent($payloads)))
            }
        }
    }
}
