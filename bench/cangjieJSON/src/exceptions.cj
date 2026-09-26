/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2024-2025. All rights reserved.
 */
package cjjson

// 类型不匹配的异常
public class JsonTypeMismatch <: Exception {
    public init(expectType: String, actualType: String) {
        super("type mismatch: expect '${expectType}', found '${actualType}'")
    }
    public init(className: String, fieldName: String, message: String) {
        super("'${className}.${fieldName}' ${message}")
    }
}

// 对应的字段不存在的异常
public class JsonFieldNotExist <: Exception {
    public init(className: String, fieldName: String) {
        super("'${className}.${fieldName}' not exist")
    }
}

// 获取 Value 失败的异常。
public class JsonGetValueException <: Exception {
    public init(message: String) {
        super(message)
    }
}
