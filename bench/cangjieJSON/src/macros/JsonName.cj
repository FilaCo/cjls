/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2024-2025. All rights reserved.
 */
macro package cjjson.macros

import std.ast.*

public macro JsonName(attr: Tokens, input: Tokens): Tokens {
    assertParentContext("JsonAdapter")

    var jsonName = "N/A"
    let expr = parseExpr(attr)
    match (expr) {
        case lce: LitConstExpr =>
            if (lce.literal.kind == STRING_LITERAL) {
                jsonName = lce.literal.value
            } else {
                diagReport(DiagReportLevel.ERROR, attr, "@JsonName only accept a String Literal",
                    "must be a String Literal")
            }
        case _ => diagReport(DiagReportLevel.ERROR, attr, "@JsonName only accept a String Literal",
            "must be a String Literal")
    }
    if (jsonName.isEmpty()) {
        diagReport(DiagReportLevel.ERROR, attr, "@JsonName has an empty String", "should not be an empty String")
    }

    let decl = parseDecl(input)
    match (decl) {
        case vd: VarDecl => GlobalInfo.current().setJsonName(vd.identifier.value, jsonName)
        case _ => diagReport(DiagReportLevel.ERROR, input, "Can only be used on VarDecl", "Expected VarDecl")
    }

    return input
}
