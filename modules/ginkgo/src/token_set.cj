package ginkgo

/**
 * A set of kinds, as bits indexed by their `ordinal`: a membership test is one shift, with nothing allocated.
 * What a grammar recovers at, or what may start a construct, is one of these, as in rust-analyzer.
 */
public struct TokenSet<K> <: Equatable<TokenSet<K>> where K <: Kind<K> {
    let words: Array<UInt64>

    init(words!: Array<UInt64>) {
        this.words = words
    }

    public init(kinds: Array<K>) {
        var size = 0
        for (k in kinds) {
            size = max(size, k.ordinal() / 64 + 1)
        }
        let w = Array<UInt64>(size, repeat: 0)
        for (k in kinds) {
            w[k.ordinal() / 64] |= 1 << UInt64(k.ordinal() % 64)
        }
        words = w
    }

    public static func empty(): TokenSet<K> {
        TokenSet<K>(words: Array<UInt64>())
    }

    public func contains(kind: K): Bool {
        let i = kind.ordinal() / 64
        i < words.size && (words[i] & (1 << UInt64(kind.ordinal() % 64))) != 0
    }

    public func union(other: TokenSet<K>): TokenSet<K> {
        let size = max(words.size, other.words.size)
        TokenSet<K>(words: Array<UInt64>(size) {i => wordAt(i) | other.wordAt(i)})
    }

    func wordAt(i: Int64): UInt64 {
        if (i < words.size) {
            words[i]
        } else {
            0
        }
    }

    public operator func ==(other: TokenSet<K>): Bool {
        for (i in 0..max(words.size, other.words.size)) {
            if (wordAt(i) != other.wordAt(i)) {
                return false
            }
        }
        true
    }

    public operator func !=(other: TokenSet<K>): Bool {
        !(this == other)
    }
}
