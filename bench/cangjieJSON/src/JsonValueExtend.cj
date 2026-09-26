/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2024-2025. All rights reserved.
 */
package cjjson

// 扩展JsonKind
public interface IJsonKindExtend {
    func toString(): String
    operator func ==(right: JsonKind): Bool
    operator func !=(right: JsonKind): Bool
}

extend JsonKind <: IJsonKindExtend {
    // 返回JsonKind对应的名字
    public func toString(): String {
        match (this) {
            case JsonKind.JsArray => "JSON Array"
            case JsonKind.JsBool => "JSON Bool"
            case JsonKind.JsFloat => "JSON Float"
            case JsonKind.JsInt => "JSON Int"
            case JsonKind.JsNull => "JSON null"
            case JsonKind.JsObject => "JSON Object"
            case JsonKind.JsString => "JSON String"
        }
    }

    // 操作符重载，支持JsonKind判等
    public operator func ==(right: JsonKind): Bool {
        match ((this, right)) {
            case (JsonKind.JsArray, JsonKind.JsArray) => return true
            case (JsonKind.JsBool, JsonKind.JsBool) => return true
            case (JsonKind.JsFloat, JsonKind.JsFloat) => return true
            case (JsonKind.JsInt, JsonKind.JsInt) => return true
            case (JsonKind.JsNull, JsonKind.JsNull) => return true
            case (JsonKind.JsObject, JsonKind.JsObject) => return true
            case (JsonKind.JsString, JsonKind.JsString) => return true
            case _ => return false
        }
    }

    // 操作符重载，支持JsonKind判不等
    public operator func !=(right: JsonKind): Bool {
        return !(this == right)
    }
}

// 扩展JsonValue
public interface IJsonValueExtend {
    // 判断JsonValue的类型
    func isBool(): Bool
    func isInt(): Bool
    func isFloat(): Bool
    func isString(): Bool
    func isObject(): Bool
    func isArray(): Bool
    func isNull(): Bool

    // 为JSON Object类型提供一系列简易的set方法，如果当前不是JSON Object类型，则写入失败，返回false。
    func setBoolValue(key: String, value: Bool): Bool
    func setIntValue(key: String, value: Int64): Bool
    func setFloatValue(key: String, value: Float64): Bool
    func setStringValue(key: String, value: String): Bool
    func setObjectValue(key: String, value: JsonObject): Bool
    func setArrayValue(key: String, value: Array<JsonValue>): Bool
    func setNullValue(key: String): Bool
    func setJsonValue(key: String, value: JsonValue): Bool

    // 为JSON Object类型提供一系列简易的get方法，如果当前不是JSON Object类型，返回default默认值。
    func getBoolValue(key: String, default!: Bool, onException!: (Exception) -> Unit): Bool
    func getIntValue(key: String, default!: Int64, onException!: (Exception) -> Unit): Int64
    func getFloatValue(key: String, default!: Float64, onException!: (Exception) -> Unit): Float64
    func getStringValue(key: String, default!: String, onException!: (Exception) -> Unit): String
    func getArrayValue(key: String, default!: Array<JsonValue>, onException!: (Exception) -> Unit): Array<JsonValue>
    func getJsonObject(key: String, default!: JsonObject, onException!: (Exception) -> Unit): JsonObject
    func getJsonValue(key: String, default!: JsonValue, onException!: (Exception) -> Unit): JsonValue
}

let emptyHandler = {_: Exception =>}

extend JsonValue <: IJsonValueExtend {
    // 判断是否是 JSON Bool 类型
    public func isBool(): Bool {
        return this.kind() == JsonKind.JsBool
    }

    // 判断是否是 JSON Int 类型
    public func isInt(): Bool {
        return this.kind() == JsonKind.JsInt
    }

    // 判断是否是 JSON Float 类型
    public func isFloat(): Bool {
        return this.kind() == JsonKind.JsFloat
    }

    // 判断是否是 JSON String 类型
    public func isString(): Bool {
        return this.kind() == JsonKind.JsString
    }

    // 判断是否是 JSON Object 类型
    public func isObject(): Bool {
        return this.kind() == JsonKind.JsObject
    }

    // 判断是否是 JSON Array 类型
    public func isArray(): Bool {
        return this.kind() == JsonKind.JsArray
    }

    // 判断是否是 JSON null
    public func isNull(): Bool {
        return this.kind() == JsonKind.JsNull
    }

    /**
     * JSON Object 写入健值对。
     *
     * @param key 要写入的键名
     * @param value 要写入的 Bool 值
     * @return 写入成功返回 true，写入失败则返回 false
     * @attention 如果当前对象不是 JSON Object 类型，则写入失败。
     */
    public func setBoolValue(key: String, value: Bool): Bool {
        match (this) {
            case obj: JsonObject =>
                obj.put(key, JsonBool(value))
                return true
            case _ => return false
        }
    }

    /**
     * JSON Object 写入健值对。
     *
     * @param key 要写入的键名
     * @param value 要写入的 Int64 值
     * @return 写入成功返回 true，写入失败则返回 false
     * @attention 如果当前对象不是 JSON Object 类型，则写入失败。
     */
    public func setIntValue(key: String, value: Int64): Bool {
        match (this) {
            case obj: JsonObject =>
                obj.put(key, JsonInt(value))
                return true
            case _ => return false
        }
    }

    /**
     * JSON Object 写入健值对。
     *
     * @param key 要写入的键名
     * @param value 要写入的 Float64 值
     * @return 写入成功返回 true，写入失败则返回 false
     * @attention 如果当前对象不是 JSON Object 类型，则写入失败。
     */
    public func setFloatValue(key: String, value: Float64): Bool {
        match (this) {
            case obj: JsonObject =>
                obj.put(key, JsonFloat(value))
                return true
            case _ => return false
        }
    }

    /**
     * JSON Object 写入健值对。
     *
     * @param key 要写入的键名
     * @param value 要写入的 String 值
     * @return 写入成功返回 true，写入失败则返回 false
     * @attention 如果当前对象不是 JSON Object 类型，则写入失败。
     */
    public func setStringValue(key: String, value: String): Bool {
        match (this) {
            case obj: JsonObject =>
                obj.put(key, JsonString(value))
                return true
            case _ => return false
        }
    }

    /**
     * JSON Object 写入健值对。
     *
     * @param key 要写入的键名
     * @param value 要写入的 JsonObject 值
     * @return 写入成功返回 true，写入失败则返回 false
     * @attention 如果当前对象不是 JSON Object 类型，则写入失败。
     */
    public func setObjectValue(key: String, value: JsonObject): Bool {
        match (this) {
            case obj: JsonObject =>
                obj.put(key, value)
                return true
            case _ => return false
        }
    }

    /**
     * JSON Object 写入健值对。
     *
     * @param key 要写入的键名
     * @param value 要写入的 Array<JsonValue> 值
     * @return 写入成功返回 true，写入失败则返回 false
     * @attention 如果当前对象不是 JSON Object 类型，则写入失败。
     */
    public func setArrayValue(key: String, value: Array<JsonValue>): Bool {
        match (this) {
            case obj: JsonObject =>
                obj.put(key, JsonArray(value))
                return true
            case _ => return false
        }
    }

    /**
     * JSON Object 写入健值对。
     *
     * @param key 要写入的键名
     * @return 写入成功返回 true，写入失败则返回 false
     * @attention 如果当前对象不是 JSON Object 类型，则写入失败。
     */
    public func setNullValue(key: String): Bool {
        match (this) {
            case obj: JsonObject =>
                obj.put(key, JsonNull())
                return true
            case _ => return false
        }
    }

    /**
     * JSON Object 写入健值对。
     *
     * @param key 要写入的键名
     * @param value 要写入的 JsonValue 值
     * @return 写入成功返回 true，写入失败则返回 false
     * @attention 如果当前对象不是 JSON Object 类型，则写入失败。
     */
    public func setJsonValue(key: String, value: JsonValue): Bool {
        match (this) {
            case obj: JsonObject =>
                obj.put(key, value)
                return true
            case _ => return false
        }
    }

    /**
     * JSON Object 读取键值对。
     *
     * @param key 要读取的键名
     * @param default 可选命名参数，默认值为 false。当健名不存在，或对应的值类型不匹配时，返回此默认值。
     * @param onException 可选命名参数，默认值为空函数。当类型不匹配时，自定义如何处理该异常。
     * @return 健名对应的 Bool 值
     * @attention 如果当前对象不是 JSON Object 类型，则返回 default 值。
     */
    public func getBoolValue(key: String, default!: Bool = false, onException!: (Exception) -> Unit = emptyHandler): Bool {
        try {
            return this.asObject().get(key)?.asBool().getValue() ?? default
        } catch (e: Exception) {
            onException(e)
        }
        return default
    }

    /**
     * JSON Object 读取键值对。
     *
     * @param key 要读取的键名
     * @param default 可选命名参数，默认值为 0。当健名不存在，或对应的值类型不匹配时，返回此默认值。
     * @param onException 可选命名参数，默认值为空函数。当类型不匹配时，自定义如何处理该异常。
     * @return 健名对应的 Int64 值
     * @attention 如果当前对象不是 JSON Object 类型，则返回 default 值。
     */
    public func getIntValue(key: String, default!: Int64 = 0, onException!: (Exception) -> Unit = emptyHandler): Int64 {
        try {
            return this.asObject().get(key)?.asInt().getValue() ?? default
        } catch (e: Exception) {
            onException(e)
        }
        return default
    }

    /**
     * JSON Object 读取键值对。
     *
     * @param key 要读取的键名
     * @param default 可选命名参数，默认值为 0.0。当健名不存在，或对应的值类型不匹配时，返回此默认值。
     * @param onException 可选命名参数，默认值为空函数。当类型不匹配时，自定义如何处理该异常。
     * @return 健名对应的 Float64 值
     * @attention 如果当前对象不是 JSON Object 类型，则返回 default 值。
     */
    public func getFloatValue(key: String, default!: Float64 = 0.0, onException!: (Exception) -> Unit = emptyHandler): Float64 {
        try {
            return this.asObject().get(key)?.asFloat().getValue() ?? default
        } catch (e: Exception) {
            onException(e)
        }
        return default
    }

    /**
     * JSON Object 读取键值对。
     *
     * @param key 要读取的键名
     * @param default 可选命名参数，默认值为空字符串。当健名不存在，或对应的值类型不匹配时，返回此默认值。
     * @param onException 可选命名参数，默认值为空函数。当类型不匹配时，自定义如何处理该异常。
     * @return 健名对应的 String 值
     * @attention 如果当前对象不是 JSON Object 类型，则返回 default 值。
     */
    public func getStringValue(key: String, default!: String = "", onException!: (Exception) -> Unit = emptyHandler): String {
        try {
            return this.asObject().get(key)?.asString().getValue() ?? default
        } catch (e: Exception) {
            onException(e)
        }
        return default
    }

    /**
     * JSON Object 读取键值对。
     *
     * @param key 要读取的键名
     * @param default 可选命名参数，默认值为空数组。当健名不存在，或对应的值类型不匹配时，返回此默认值。
     * @param onException 可选命名参数，默认值为空函数。当类型不匹配时，自定义如何处理该异常。
     * @return 健名对应的 Array<JsonValue> 值
     * @attention 如果当前对象不是 JSON Object 类型，则返回 default 值。
     */
    public func getArrayValue(key: String, default!: Array<JsonValue> = Array(),
        onException!: (Exception) -> Unit = emptyHandler): Array<JsonValue> {
        try {
            return this.asObject().get(key)?.asArray().getItems().toArray() ?? default
        } catch (e: Exception) {
            onException(e)
        }
        return default
    }

    /**
     * JSON Object 读取键值对。
     *
     * @param key 要读取的键名
     * @param default 可选命名参数，默认值为空数组。当健名不存在，或对应的值类型不匹配时，返回此默认值。
     * @param onException 可选命名参数，默认值为空函数。当类型不匹配时，自定义如何处理该异常。
     * @return 健名对应的 JsonObject 值
     * @attention 如果当前对象不是 JSON Object 类型，则返回 default 值。
     */
    public func getJsonObject(key: String, default!: JsonObject = JsonObject(),
        onException!: (Exception) -> Unit = emptyHandler): JsonObject {
        try {
            return this.asObject().get(key)?.asObject() ?? default
        } catch (e: Exception) {
            onException(e)
        }
        return default
    }

    /**
     * JSON Object 读取键值对。
     *
     * @param key 要读取的键名
     * @param default 可选命名参数，默认值为空数组。当健名不存在，或对应的值类型不匹配时，返回此默认值。
     * @param onException 可选命名参数，默认值为空函数。当类型不匹配时，自定义如何处理该异常。
     * @return 健名对应的 JsonValue 值
     * @attention 如果当前对象不是 JSON Object 类型，则返回 default 值。
     */
    public func getJsonValue(key: String, default!: JsonValue = JsonNull(),
        onException!: (Exception) -> Unit = emptyHandler): JsonValue {
        try {
            return this.asObject().get(key) ?? default
        } catch (e: Exception) {
            onException(e)
        }
        return default
    }
}
