package calca

import std.deriving.*

/**
 * How rarely an input is expected to change. A memo remembers the lowest durability among what it
 * read, so a revision that changed only inputs more durable than that one lets it be reused without
 * walking its dependencies: the sources of a project's dependencies are `High`, the file being
 * typed in is `Low`.
 */
@Derive[Equatable, Comparable]
public enum Durability <: ToString {
    | Low
    | Medium
    | High

    prop rank: Int64 {
        get() {
            match (this) {
                case Low => 0
                case Medium => 1
                case High => 2
            }
        }
    }

    /**
     * The bare name: a derived `toString` would qualify it with the type.
     */
    public func toString(): String {
        match (this) {
            case Low => "Low"
            case Medium => "Medium"
            case High => "High"
        }
    }
}

const DURABILITIES: Int64 = 3
