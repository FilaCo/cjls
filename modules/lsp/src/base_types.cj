package lsp

import std.collection.{HashMap, ArrayList}
import std.convert.Parsable
import std.deriving.*
import stdx.encoding.json.stream.*

public enum LspAny <: JsonSerializable & JsonDeserializable<LspAny> {
    | LspNull
    | LspBool(Bool)
    | LspInteger(Int64)
    | LspString(String)
    | LspArray(Array<LspAny>)
    | LspObject(HashMap<String, LspAny>)

    @Frozen
    public static func fromJson(r: JsonReader): LspAny {
        r.peek().map {
            tok => match (tok) {
                case JsonNull =>
                    r.skip()
                    LspNull
                case JsonBool => LspBool(r.readValue())
                case JsonNumber => LspInteger(r.readValue()) // TODO: LspDecimal?
                case JsonString => LspString(r.readValue())
                case BeginArray =>
                    r.startArray()
                    let items = ArrayList<LspAny>()
                    while (r.peek() != EndArray) {
                        items.add(fromJson(r))
                    }
                    r.endArray()
                    LspArray(items.toArray())
                case BeginObject =>
                    r.startObject()
                    let items = HashMap<String, LspAny>()
                    while (r.peek() != EndObject) {
                        let k = r.readName()
                        let v = fromJson(r)
                        items.add(k, v)
                    }
                    r.endObject()
                    LspObject(items)
                case _ => throw Exception() // TODO: custom exception
            }
        }.getOrThrow() // TODO: custom exception
    }

    @Frozen
    public func toJson(w: JsonWriter): Unit {
        match (this) {
            case LspNull => w.writeNullValue()
            case LspBool(b) => w.writeValue(b)
            case LspInteger(i) => w.writeValue(i)
            case LspString(s) => w.writeValue(s)
            case LspArray(a) => w.writeValue(a)
            case LspObject(obj) =>
                w.startObject()
                for ((k, v) in obj) {
                    w.writeName(k).writeValue(v)
                }
                w.endObject()
        }
    }
}

/**
 * `integer | string` type.
 */
@Derive[Equatable]
public enum IntegerOrString <: JsonSerializable & JsonDeserializable<IntegerOrString> {
    | Integer(Int64)
    | String(String)

    /**
     * @throws IllegalArgumentException - If input is empty, or not either a string or integer
     */
    @Frozen
    public static func fromJson(r: JsonReader): IntegerOrString {
        r.peek().map {
            v: JsonToken => match (v) {
                case JsonNumber => IntegerOrString.Integer(Int64.parse(r.readValue()))
                case JsonString => IntegerOrString.String(r.readValue())
                case _ => throw IllegalArgumentException("expected string or integer")
            }
        }.getOrThrow {=> IllegalArgumentException("expected json token")}
    }

    @Frozen
    public func toJson(w: JsonWriter): Unit {
        match (this) {
            case Integer(v) => w.writeValue(v)
            case String(v) => w.writeValue(v)
        }
    }
}
