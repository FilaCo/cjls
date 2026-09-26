/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2024-2025. All rights reserved.
 */
package cjjson

import std.collection.*
import stdx.encoding.json.*

extend Int64 <: IJsonAdapter<Int64> {
    public static func fromJsonValue(jsonValue: JsonValue): Int64 {
        match (jsonValue) {
            case v: JsonInt => return v.getValue()
            case _ => throw JsonTypeMismatch("Int64", jsonValue.kind().toString())
        }
    }

    public func toJsonValue(): JsonValue {
        return JsonInt(this)
    }
}

extend Int32 <: IJsonAdapter<Int32> {
    public static func fromJsonValue(jsonValue: JsonValue): Int32 {
        match (jsonValue) {
            case v: JsonInt => return Int32(v.getValue())
            case _ => throw JsonTypeMismatch("Int32", jsonValue.kind().toString())
        }
    }

    public func toJsonValue(): JsonValue {
        return JsonInt(Int64(this))
    }
}

extend Int16 <: IJsonAdapter<Int16> {
    public static func fromJsonValue(jsonValue: JsonValue): Int16 {
        match (jsonValue) {
            case v: JsonInt => return Int16(v.getValue())
            case _ => throw JsonTypeMismatch("Int16", jsonValue.kind().toString())
        }
    }

    public func toJsonValue(): JsonValue {
        return JsonInt(Int64(this))
    }
}

extend Int8 <: IJsonAdapter<Int8> {
    public static func fromJsonValue(jsonValue: JsonValue): Int8 {
        match (jsonValue) {
            case v: JsonInt => return Int8(v.getValue())
            case _ => throw JsonTypeMismatch("Int8", jsonValue.kind().toString())
        }
    }

    public func toJsonValue(): JsonValue {
        return JsonInt(Int64(this))
    }
}

extend UInt64 <: IJsonAdapter<UInt64> {
    public static func fromJsonValue(jsonValue: JsonValue): UInt64 {
        match (jsonValue) {
            case v: JsonInt => return UInt64(v.getValue())
            case _ => throw JsonTypeMismatch("UInt64", jsonValue.kind().toString())
        }
    }

    public func toJsonValue(): JsonValue {
        return JsonInt(Int64(this))
    }
}

extend UInt32 <: IJsonAdapter<UInt32> {
    public static func fromJsonValue(jsonValue: JsonValue): UInt32 {
        match (jsonValue) {
            case v: JsonInt => return UInt32(v.getValue())
            case _ => throw JsonTypeMismatch("UInt32", jsonValue.kind().toString())
        }
    }

    public func toJsonValue(): JsonValue {
        return JsonInt(Int64(this))
    }
}

extend UInt16 <: IJsonAdapter<UInt16> {
    public static func fromJsonValue(jsonValue: JsonValue): UInt16 {
        match (jsonValue) {
            case v: JsonInt => return UInt16(v.getValue())
            case _ => throw JsonTypeMismatch("UInt16", jsonValue.kind().toString())
        }
    }

    public func toJsonValue(): JsonValue {
        return JsonInt(Int64(this))
    }
}

extend UInt8 <: IJsonAdapter<UInt8> {
    public static func fromJsonValue(jsonValue: JsonValue): UInt8 {
        match (jsonValue) {
            case v: JsonInt => return UInt8(v.getValue())
            case _ => throw JsonTypeMismatch("UInt8", jsonValue.kind().toString())
        }
    }

    public func toJsonValue(): JsonValue {
        return JsonInt(Int64(this))
    }
}

extend Float64 <: IJsonAdapter<Float64> {
    public static func fromJsonValue(jsonValue: JsonValue): Float64 {
        match (jsonValue) {
            case v: JsonFloat => return v.getValue()
            case _ => throw JsonTypeMismatch("Float64", jsonValue.kind().toString())
        }
    }

    public func toJsonValue(): JsonValue {
        return JsonFloat(this)
    }
}

extend Float32 <: IJsonAdapter<Float32> {
    public static func fromJsonValue(jsonValue: JsonValue): Float32 {
        match (jsonValue) {
            case v: JsonFloat => return Float32(v.getValue())
            case _ => throw JsonTypeMismatch("Float32", jsonValue.kind().toString())
        }
    }

    public func toJsonValue(): JsonValue {
        return JsonFloat(Float64(this))
    }
}

extend Float16 <: IJsonAdapter<Float16> {
    public static func fromJsonValue(jsonValue: JsonValue): Float16 {
        match (jsonValue) {
            case v: JsonFloat => return Float16(v.getValue())
            case _ => throw JsonTypeMismatch("Float16", jsonValue.kind().toString())
        }
    }

    public func toJsonValue(): JsonValue {
        return JsonFloat(Float64(this))
    }
}

extend String <: IJsonAdapter<String> {
    public static func fromJsonValue(jsonValue: JsonValue): String {
        match (jsonValue) {
            case v: JsonString => return v.getValue()
            case _ => throw JsonTypeMismatch("String", jsonValue.kind().toString())
        }
    }

    public func toJsonValue(): JsonValue {
        return JsonString(this)
    }
}

extend Bool <: IJsonAdapter<Bool> {
    public static func fromJsonValue(jsonValue: JsonValue): Bool {
        match (jsonValue) {
            case v: JsonBool => return v.getValue()
            case _ => throw JsonTypeMismatch("Bool", jsonValue.kind().toString())
        }
    }

    public func toJsonValue(): JsonValue {
        return JsonBool(this)
    }
}

extend<T> Option<T> <: IJsonAdapter<Option<T>> where T <: IJsonAdapter<T> {
    public static func fromJsonValue(jsonValue: JsonValue): Option<T> {
        if (jsonValue is JsonNull) {
            return None
        } else {
            return T.fromJsonValue(jsonValue)
        }
    }

    public func toJsonValue(): JsonValue {
        if (let Some(v) <- this) {
            v.toJsonValue()
        } else {
            JsonNull()
        }
    }
}

extend<T> Array<T> <: IJsonAdapter<Array<T>> where T <: IJsonAdapter<T> {
    public static func fromJsonValue(jsonValue: JsonValue): Array<T> {
        match (jsonValue) {
            case arr: JsonArray => return Array<T>(arr.size(), {index => T.fromJsonValue(arr[index])})
            case _ => throw JsonTypeMismatch("Array", jsonValue.kind().toString())
        }
    }

    public func toJsonValue(): JsonValue {
        let list = Array<JsonValue>(this.size, {index => this[index].toJsonValue()})
        return JsonArray(list)
    }
}

extend<T> ArrayList<T> <: IJsonAdapter<ArrayList<T>> where T <: IJsonAdapter<T> {
    public static func fromJsonValue(jsonValue: JsonValue): ArrayList<T> {
        match (jsonValue) {
            case arr: JsonArray => return ArrayList<T>(arr.size(), {index => T.fromJsonValue(arr[index])})
            case _ => throw JsonTypeMismatch("ArrayList", jsonValue.kind().toString())
        }
    }

    public func toJsonValue(): JsonValue {
        let list = Array<JsonValue>(this.size, {index => this[index].toJsonValue()})
        return JsonArray(list)
    }
}

extend<T> HashSet<T> <: IJsonAdapter<HashSet<T>> where T <: IJsonAdapter<T> & Hashable & Equatable<T> {
    public static func fromJsonValue(jsonValue: JsonValue): HashSet<T> {
        match (jsonValue) {
            case arr: JsonArray => return HashSet<T>(arr.size(), {index => T.fromJsonValue(arr[index])})
            case _ => throw JsonTypeMismatch("HashSet", jsonValue.kind().toString())
        }
    }

    public func toJsonValue(): JsonValue {
        let ret = JsonArray()
        for (item in this) {
            ret.add(item.toJsonValue())
        }
        return ret
    }
}

extend<V> HashMap<String, V> <: IJsonAdapter<HashMap<String, V>> where V <: IJsonAdapter<V> {
    public static func fromJsonValue(jsonValue: JsonValue): HashMap<String, V> {
        let map = HashMap<String, V>()
        match (jsonValue) {
            case obj: JsonObject => for ((key, value) in obj.getFields()) {
                map.add(key, V.fromJsonValue(value))
            }
            case _ => throw JsonTypeMismatch("HashMap", jsonValue.kind().toString())
        }
        return map
    }

    public func toJsonValue(): JsonValue {
        let obj = JsonObject()
        for ((key, item) in this) {
            obj.put(key, item.toJsonValue())
        }
        return obj
    }
}
