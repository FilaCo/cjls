/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2024-2025. All rights reserved.
 */
macro package cjjson.macros

import std.ast.*

func isOptionType(node: TypeNode): Bool {
    match (node) {
        case pt: PrefixType => return true
        case rt: RefType =>
            if (rt.identifier.value == "Option") {
                return true
            } else {
                return false
            }
        case _ => return false
    }
}

func getOptionBaseType(node: TypeNode): Tokens {
    match (node) {
        case pt: PrefixType => return pt.baseType.toTokens()
        case rt: RefType =>
            if (rt.identifier.value == "Option") {
                return rt.typeArguments.toTokens()
            } else {
                return node.toTokens()
            }
        case _ => return node.toTokens()
    }
}

func unwrapRawIdentifier(identifier: Token): String {
    let name = identifier.value
    if (name.startsWith("`") && name.endsWith("`")) {
        return name[1..name.size - 1]
    } else {
        return name
    }
}
