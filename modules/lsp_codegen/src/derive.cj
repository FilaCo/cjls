package lsp_codegen

import std.ast.*
import std.collection.*
import stdxx.*

enum DeriveIr {
    | Equatable
    | Hashable
    | Serializable(SerializableTypeOptions)
}

struct SerializableTypeOptions <: ToTokens {
    SerializableTypeOptions(let transparent!: Bool = false, let skipNone!: Bool = false, let tag!: ?SerializableTag = None) {}

    public func toTokens(): Tokens {
        let options = ArrayList<Tokens>()
        if (transparent) {
            options.add(quote(transparent))
        }
        if (skipNone) {
            options.add(quote(skipNone))
        }
        if (let Some(t) <- tag) {
            options.add(quote(tag: $(t.field), value: $(t.value)))
        }

        markerOf(options)
    }
}

struct SerializableTag {
    SerializableTag(let field!: String, let value!: String) {}
}

struct SerializableMemberOptions <: ToTokens {
    SerializableMemberOptions(let value!: ?IntegerOrString = None, let other!: Bool = false) {}

    public func toTokens(): Tokens {
        let options = ArrayList<Tokens>()
        if (let Some(v) <- value) {
            options.add(quote(value: $v))
        }
        if (other) {
            options.add(quote(other))
        }

        markerOf(options)
    }
}

private func markerOf(options: Iterable<Tokens>): Tokens {
    match (joined(options)) {
        case Some(joinedOptions) => quote(@DeriveExtSerializable[$joinedOptions])
        case None => Tokens()
    }
}

func serializableMarkerOf(options: ?SerializableMemberOptions): Tokens {
    options.map {it: SerializableMemberOptions => it.toTokens()} ?? Tokens()
}

extend CjEmitter {
    /**
     * The order is load-bearing: macros expand inside out and `@DeriveExt` appends to whatever
     * `@Derive` produced, so it has to be the outer one, with its type-level marker inside it.
     */
    func emitDerives(derives: Collection<DeriveIr>): Unit {
        let std = ArrayList<Tokens>()
        let ext = ArrayList<Tokens>()
        var typeMarker = Tokens()
        for (derive in derives) {
            match (derive) {
                case DeriveIr.Equatable => std.add(quote(Equatable))
                case DeriveIr.Hashable => std.add(quote(Hashable))
                case Serializable(options) =>
                    ext.add(quote(Serializable))
                    typeMarker = options.toTokens()
            }
        }

        if (let Some(names) <- joined(ext)) {
            emitln(quote(@DeriveExt[$names]))
        }
        if (typeMarker.size > 0) {
            emitln(typeMarker)
        }
        if (let Some(names) <- joined(std)) {
            emitln(quote(@Derive[$names]))
        }
    }
}

private func joined(parts: Iterable<Tokens>): ?Tokens {
    parts |> reduce {acc: Tokens, it: Tokens => quote($acc, $it)}
}
