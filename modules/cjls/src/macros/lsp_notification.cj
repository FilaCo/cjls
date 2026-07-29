macro package cjls.macros

import std.ast.*

public macro LspNotification(attrs: Tokens, input: Tokens): Tokens {
    let args = parseAttrs(attrs)
    input
}

func extendLspNotification(genericParam: Tokens, ident: Token, genericConstraint: Tokens, paramTy: Tokens,
    methodBody: Tokens, handleBody: Tokens): Tokens {
    quote(
        extend $genericParam $ident $genericParam $genericConstraint <: LspNotification<$paramTy> {
            @Frozen
            public static prop METHOD: String {
                get() {
                    $methodBody
                }
            }

            @Frozen
            public static func handle(params: $paramTy, ctx: GlobalContext): Unit {
                $handleBody
            }
        }
    )
}
