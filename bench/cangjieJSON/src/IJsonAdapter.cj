/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2024-2025. All rights reserved.
 */
package cjjson

public import stdx.encoding.json.*

public interface IJsonAdapter<T> {
    static func fromJson(str: String): T {
        fromJsonValue(JsonValue.fromStr(str))
    }

    static func fromJsonValue(jsonValue: JsonValue): T

    func toJson(): String {
        toJsonValue().toString()
    }

    func toJsonValue(): JsonValue
}
