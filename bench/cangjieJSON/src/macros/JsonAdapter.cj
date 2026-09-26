/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2024-2025. All rights reserved.
 */
macro package cjjson.macros

import std.ast.*

// @JsonAdapter 修饰 class 时允许使用的属性
class JsonAdapterClassAttr {
    public static const WITH_SUPER_CLASS: String = "withSuperClass"
    public static const WITH_GENERIC_TYPE: String = "withGenericType"
    public static const ALLOW_NULL: String = "allowNull"

    public static func availableAttrs(): String {
        return "[${WITH_SUPER_CLASS}, ${WITH_GENERIC_TYPE}, ${ALLOW_NULL}]"
    }
}

// 带属性的宏定义
public macro JsonAdapter(attr: Tokens, input: Tokens): Tokens {
    return jsonAdapterImpl(attr, input)
}

// 不带属性的宏定义
public macro JsonAdapter(input: Tokens): Tokens {
    return jsonAdapterImpl(Tokens(), input)
}

func jsonAdapterImpl(attr: Tokens, input: Tokens): Tokens {
    var ret = input
    let decl = parseDecl(input)
    match (decl) {
        case cd: ClassDecl => ret = HandleClass(cd).doExpend(attr)
        case ed: EnumDecl => ret = HandleEnum(ed).doExpend(attr)
        case sd: StructDecl => ret = HandleStruct(sd).doExpend(attr)
        case _ => diagReport(DiagReportLevel.ERROR, input, "Can only be used on class or struct types",
            "Expect class or struct")
    }

    // 展开完一个class之后，需要重置全局信息，以便展开下一个class 时全局数据保证是空的
    GlobalInfo.current().reset()

    return ret
}
