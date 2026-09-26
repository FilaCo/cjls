/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2024-2025. All rights reserved.
 */
macro package cjjson.macros

import std.collection.*

// 用于记录当前正在进行宏展开的 class/struct/enum 类型的成员列表的嵌套宏信息。
class GlobalInfo {
    private static var instance = GlobalInfo()

    private let jsonIgnoreSet = HashSet<String>() // 使用了 @JsonIgnore 的字段列表
    private let jsonIgnoreNullSet = HashSet<String>() // 使用了 @JsonIgnoreNull 的字段列表
    private let jsonNameMap = HashMap<String, String>() // 使用了 @JsonName 的哈希表（key是类的字段名称，value是json字符串里的字段名称）
    private let jsonDefaulteSet = HashSet<String>() // 使用了 @JsonDefault 的字段列表

    private init() {
    }

    public static func current(): GlobalInfo {
        return instance
    }

    public func reset(): Unit {
        jsonIgnoreSet.clear()
        jsonIgnoreNullSet.clear()
        jsonNameMap.clear()
        jsonDefaulteSet.clear()
    }

    public func setJsonIgnore(fieldName: String): Unit {
        jsonIgnoreSet.add(fieldName)
    }

    public func isJsonIgnore(fieldName: String): Bool {
        return jsonIgnoreSet.contains(fieldName)
    }

    public func setJsonIgnoreNull(fieldName: String): Unit {
        jsonIgnoreNullSet.add(fieldName)
    }

    public func isJsonIgnoreNull(fieldName: String): Bool {
        return jsonIgnoreNullSet.contains(fieldName)
    }

    public func setJsonName(fieldName: String, jsonName: String): Unit {
        jsonNameMap.add(fieldName, jsonName)
    }

    public func getJsonName(fieldName: String): ?String {
        return jsonNameMap.get(fieldName)
    }

    public func setJsonDefault(fieldName: String): Unit {
        jsonDefaulteSet.add(fieldName)
    }

    public func isJsonDefault(fieldName: String): Bool {
        return jsonDefaulteSet.contains(fieldName)
    }
}
