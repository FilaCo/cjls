package lsp_codegen

import std.ast.*
import std.collection.*
import stdxx.*

/**
 * An interface a generated declaration derives.
 */
enum DeriveIr {
    | Equatable
    | Hashable
    | Serializable(SerializableTypeOptions)
}

struct SerializableTypeOptions <: ToTokens {
    SerializableTypeOptions(let transparent!: Bool = false) {}

    public func toTokens(): Tokens {
        markerOf(if (transparent) {
            [quote(transparent)]
        } else {
            []
        })
    }
}

/**
 * @note only a member of a type that derives `Serializable` may carry it - the marker does not
 *       compile anywhere else.
 */
struct SerializableMemberOptions <: ToTokens {
    SerializableMemberOptions(let value!: ?IntegerOrString = None) {}

    public func toTokens(): Tokens {
        markerOf(if (let Some(v) <- value) {
            [quote(value: $v)]
        } else {
            []
        })
    }
}

private func markerOf(options: Array<Tokens>): Tokens {
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
