macro package stdxx.deriving

import std.ast.*

extend StructDecl {
    // Returns the primary constructor declared directly in the struct body,
    // or None when the struct has none.
    func getPrimaryCtor(): ?PrimaryCtorDecl {
        for (decl in body.decls) {
            match (decl) {
                case pcd: PrimaryCtorDecl => return pcd
                case _ => ()
            }
        }
        None
    }

    func getGenericFragments(): (Tokens, Tokens) {
        if (isGenericDecl) {
            (genericParam.toTokens(), genericConstraint.toTokens())
        } else {
            (Tokens(), Tokens())
        }
    }
}
