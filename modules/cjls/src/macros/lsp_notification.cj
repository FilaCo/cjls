macro package cjls.macros

import std.ast.*

public macro LspNotification(attrs: Tokens, input: Tokens): Tokens {
    input
}

func extendLspNotification(): Tokens {
    quote(
        extend $genericParam $ident $genericParam $genericConstraint <: LspNotification<$paramTy> {
            @Frozen
            public static prop METHOD: String {
                get() {
                    $method
                }
            }

            @Frozen
            public static func handle(params: $paramTy, ctx: GlobalContext): Unit {
                $handleImplCall
            }
        }
    )
}