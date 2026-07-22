package lsp

import std.collection.{HashMap, ArrayList}
import std.io.ByteBuffer
import std.deriving.*
import stdx.encoding.json.stream.*

public enum LspAny <: JsonSerializable & JsonDeserializable<LspAny> {
    | LspNull
    | LspBool(Bool)
    | LspInteger(Int64)
    | LspString(String)
    | LspArray(Array<LspAny>)
    | LspObject(HashMap<String, LspAny>)

    /**
     * @throws IllegalStateException - if EOF met or faced malformed JSON
     */
    @Frozen
    public static func fromJson(r: JsonReader): LspAny {
        if (let Some(tok) <- r.peek()) {
            return match (tok) {
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
                case _ => throw IllegalStateException("malformed JSON")
            }
        }

        throw IllegalStateException("expected LspAny, found EOF")
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
 * TODO: is it possible to get rid of this ugly round-trip?
 */
@Frozen
public func toLspAny<T>(v: T): LspAny where T <: JsonSerializable {
    let bb = ByteBuffer()
    let jw = JsonWriter(bb)
    v.toJson(jw)
    jw.flush()
    let jr = JsonReader(bb)
    LspAny.fromJson(jr)
}

@Frozen
public func fromLspAny<T>(v: LspAny): T where T <: JsonDeserializable<T> {
    let bb = ByteBuffer()
    let jw = JsonWriter(bb)
    v.toJson(jw)
    jw.flush()
    let jr = JsonReader(bb)
    T.fromJson(jr)
}

@Frozen
public func toJsonString<T>(v: T): String where T <: JsonSerializable {
    let bb = ByteBuffer()
    let jw = JsonWriter(bb)
    v.toJson(jw)
    jw.flush()
    String.fromUtf8(bb.bytes())
}

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
    @Frozen
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

    @Frozen
    public func toJson(w: JsonWriter): Unit {
        match (this) {
            case Integer(v) => w.writeValue(v)
            case String(v) => w.writeValue(v)
        }
    }

    @Frozen
    public func toString(): String {
        toJsonString(this)
    }
}

sealed abstract class LspException <: Exception {
    LspException() {
    }

    init(str: String) {
        super(str)
    }
}
