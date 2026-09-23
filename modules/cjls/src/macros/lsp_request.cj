macro package cjls.macros

import std.ast.*

public macro LspRequest(attrs: Tokens, input: Tokens): Tokens {
    input
}

private func extendLspRequest(genericParam: Tokens, ident: Token, paramTy: Tokens, resultTy: Tokens,
    genericConstraint: Tokens, methodExpr: Expr, handleCall: Tokens): Tokens {
    quote(
        extend $genericParam $ident $genericParam <: LspRequest<$paramTy, $resultTy> $genericConstraint {
            public static prop METHOD: String {
                get() {
                    $methodExpr
                }
            }

            
            public static func handle(params: $paramTy, ctx: GlobalContext): $resultTy {
                $handleCall
            }
        }
    )
}
