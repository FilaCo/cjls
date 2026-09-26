package ginkgo

/**
 * What a tree needs from the type that names its nodes and tokens: in practice the language's enum of kinds.
 * `toString` is what `debugDump` prints for it.
 */
public interface Kind<K> <: Hashable & Equatable<K> & ToString {
    /**
     * The kind's position among all of its type's, from 0 and with no gaps: what a `TokenSet` is indexed by.
     */
    func ordinal(): Int64
}
