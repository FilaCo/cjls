package ginkgo

import std.deriving.*

@Derive[Equatable, Hashable]
enum TestKind {
    | Root
    | Inner
    | Leaf
    | Word
    | Space

    public func toString(): String {
        match (this) {
            case Root => "Root"
            case Inner => "Inner"
            case Leaf => "Leaf"
            case Word => "Word"
            case Space => "Space"
        }
    }
}

extend TestKind <: Kind<TestKind> {}

/**
 * Root [ "a" " " Inner [ "b" Leaf [] "c" ] " " Leaf [ "d" ] ], text "a bc d".
 */
func sampleTree(): SyntaxNode<TestKind> {
    let b = GreenNodeBuilder<TestKind>()
    b.startNode(Root)
    b.token(Word, "a")
    b.token(Space, " ")
    b.startNode(Inner)
    b.token(Word, "b")
    b.startNode(Leaf)
    b.finishNode()
    b.token(Word, "c")
    b.finishNode()
    b.token(Space, " ")
    b.startNode(Leaf)
    b.token(Word, "d")
    b.finishNode()
    b.finishNode()
    SyntaxNode.newRoot(b.finish())
}
