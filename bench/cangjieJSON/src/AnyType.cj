/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2024-2025. All rights reserved.
 */
package cjjson

// 用于表示任意类型。
public class AnyType <: IJsonAdapter<AnyType> {
    public var jsonValue: JsonValue

    public init() {
        this.jsonValue = JsonNull()
    }

    public init(value: JsonValue) {
        this.jsonValue = value
    }

    public func isArray(): Bool {
        return this.jsonValue.isArray()
    }

    public func isBool(): Bool {
        return this.jsonValue.isBool()
    }

    public func isFloat(): Bool {
        return this.jsonValue.isFloat()
    }

    public func isInt(): Bool {
        return this.jsonValue.isInt()
    }

    public func isNull(): Bool {
        return this.jsonValue.isNull()
    }

    public func isObject(): Bool {
        return this.jsonValue.isObject()
    }

    public func isString(): Bool {
        return this.jsonValue.isString()
    }

    // 如果类型不匹配，会抛出异常。
    public func getValue<T>(): T where T <: IJsonAdapter<T> {
        try {
            T.fromJsonValue(this.jsonValue)
        } catch (e: Exception) {
            throw JsonGetValueException("AnyType.getValue<T>() failed: ${e.message}")
        }
    }

    public static func fromJsonValue(value: JsonValue): AnyType {
        return AnyType(value)
    }

    public func toJsonValue(): JsonValue {
        return jsonValue
    }
}
