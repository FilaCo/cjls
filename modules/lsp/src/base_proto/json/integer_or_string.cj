package lsp.base_proto.json

import stdx.encoding.json.stream.*
import std.convert.Parsable

/**
 * `integer | string` type.
 */
public enum IntegerOrString <: Equatable<IntegerOrString> & JsonSerializable & JsonDeserializable<IntegerOrString> {
    Integer(Int32) | String(String)

    public operator func ==(other: IntegerOrString) {
        match ((this, other)) {
            case (Integer(lhs), Integer(rhs)) => lhs == rhs
            case (String(lhs), String(rhs)) => lhs == rhs
            case _ => false
        }
    }

    /**
     * @throws IllegalArgumentException - If input is empty, or not either a string or integer
     */
    public static func fromJson(r: JsonReader): IntegerOrString {
        r.peek().map {
            v: JsonToken => match (v) {
                case JsonNumber => IntegerOrString.Integer(Int32.parse(r.readValue()))
                case JsonString => IntegerOrString.String(r.readValue())
                case _ => throw IllegalArgumentException("expected string or integer")
            }
        }.getOrThrow {=> IllegalArgumentException("expected json token")}
    }

    public func toJson(w: JsonWriter): Unit {
        match (this) {
            case Integer(v) => w.writeValue(v)
            case String(v) => w.writeValue(v)
        }
    }
}
