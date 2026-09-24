package ginkgo

/**
 * What a tree needs from the type that names its nodes and tokens: in practice the language's enum of kinds.
 * `toString` is what `debugDump` prints for it.
 */
public interface Kind<K> <: Hashable & Equatable<K> & ToString {}
