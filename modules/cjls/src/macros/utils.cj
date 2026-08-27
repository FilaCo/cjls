macro package cjls.macros

import std.ast.*

func lexAttrs(attrs: Tokens): Array<Argument> {
    match (parseExpr(quote(dummy($attrs)))) {
        case ce: CallExpr => ce.arguments.toArray()
        case _ => []
    }
}

extend Decl {
    // TODO: to some lib?
    func getGenericFragments(): (Tokens, Tokens) {
        if (isGenericDecl) {
            (genericParam.toTokens(), genericConstraint.toTokens())
        } else {
            (Tokens(), Tokens())
        }
    }
}
