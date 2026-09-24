package ginkgo

public enum Direction {
    | Next
    | Prev
}

/**
 * A step of a preorder walk: every element is entered, then, after all it contains, left.
 */
public enum WalkEvent<T> {
    | Enter(T)
    | Leave(T)

    public func value(): T {
        match (this) {
            case Enter(v) => v
            case Leave(v) => v
        }
    }
}

/**
 * The tokens at an offset: the one it is inside of, or the two it is between.
 */
public enum TokenAtOffset<T> {
    | NoToken
    | Single(T)
    | Between(T, T)

    /**
     * Of two tokens, the one ending at the offset.
     */
    public func leftBiased(): ?T {
        match (this) {
            case NoToken => None
            case Single(t) => t
            case Between(left, _) => left
        }
    }

    /**
     * Of two tokens, the one starting at the offset.
     */
    public func rightBiased(): ?T {
        match (this) {
            case NoToken => None
            case Single(t) => t
            case Between(_, right) => right
        }
    }
}

/**
 * `first`, then `advance` of it, and so on while there is one.
 */
class Successors<T> <: Iterator<T> {
    var upcoming: ?T

    Successors(first: ?T, let advance: (T) -> ?T) {
        upcoming = first
    }

    public func next(): ?T {
        match (upcoming) {
            case Some(current) =>
                upcoming = advance(current)
                current
            case None => None
        }
    }
}
