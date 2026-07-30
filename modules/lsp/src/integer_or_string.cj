package lsp

import std.deriving.*
import stdx.encoding.json.stream.*

/**
 * `integer | string` type.
 */
@Derive[Equatable]
public enum IntegerOrString <: JsonSerializable & JsonDeserializable<IntegerOrString> & ToString {
    | Integer(Int64)
    | String(String)

    /**
     * @throws IllegalStateException - If input is empty, or not either a string or integer
     */
    public static func fromJson(r: JsonReader): IntegerOrString {
        if (let Some(tok) <- r.peek()) {
            return match (tok) {
                case JsonNumber => IntegerOrString.Integer(r.readValue())
                case JsonString => IntegerOrString.String(r.readValue())
                case _ => throw IllegalStateException("expected integer or string")
            }
        }

        throw IllegalStateException("expected integer or string, found EOF")
    }

    public func toJson(w: JsonWriter): Unit {
        match (this) {
            case Integer(v) => w.writeValue(v)
            case String(v) => w.writeValue(v)
        }
    }

    public func toString(): String {
        toJsonString(this)
    }
}
