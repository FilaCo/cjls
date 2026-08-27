package lsp_codegen

import std.ast.*
import std.collection.*

enum DerivingIr {
    | Equatable
    | Hashable
}

extend CjEmitter {
    func withDerivings(derivingIrs: Collection<DerivingIr>, body: () -> Unit): Unit {
        var derivingTokens = derivingIrs |> map {
            it => match (it) {
                case DerivingIr.Equatable => Token(IDENTIFIER, "Equatable")
                case DerivingIr.Hashable => Token(IDENTIFIER, "Hashable")
            }.toTokens()
        } |> reduce {acc, it => quote($acc, $it)}

        if (let Some(d) <- derivingTokens) {
            emitln(quote(@Derive[$d]))
        }

        body()
    }
}
