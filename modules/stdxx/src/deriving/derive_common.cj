macro package stdxx.deriving

import std.ast.*

// Returns the primary constructor declared directly in the struct body,
// or None when the struct has none.
func primaryCtorOf(sd: StructDecl): ?PrimaryCtorDecl {
    for (decl in sd.body.decls) {
        match (decl) {
            case pcd: PrimaryCtorDecl => return pcd
            case _ => ()
        }
    }
    None
}

func genericFragments(sd: StructDecl): (Tokens, Tokens) {
    if (sd.isGenericDecl) {
        (sd.genericParam.toTokens(), sd.genericConstraint.toTokens())
    } else {
        (Tokens(), Tokens())
    }
}
