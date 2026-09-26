/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2024-2025. All rights reserved.
 */
macro package cjjson.macros

import std.ast.*

class FieldInfo {
    public let vd: VarDecl
    public var isIgnore: Bool
    public var isIgnoreNull: Bool
    public var useDefault: Bool
    public var jsonName: ?String
    public var typeNode: ?TypeNode = None

    public var isPrivate: Bool = false
    public var isStatic: Bool = false

    public init(vd: VarDecl) {
        this.vd = vd
        let identifierString = vd.identifier.value
        isIgnore = GlobalInfo.current().isJsonIgnore(identifierString)
        isIgnoreNull = GlobalInfo.current().isJsonIgnoreNull(identifierString)
        useDefault = GlobalInfo.current().isJsonDefault(identifierString)
        jsonName = GlobalInfo.current().getJsonName(identifierString)

        // 没有用 @JsonIgnore 标记的成员，检查是否显式的声明了其类型
        if (!isIgnore) {
            try {
                typeNode = vd.declType
            } catch (e: ASTException) {
                diagReport(DiagReportLevel.ERROR, vd.identifier.toTokens(),
                    "filed without @JsonIgnore must explicitly declare its type", "must explicitly declare its type")
            }
        }

        for (mod in vd.modifiers) {
            match (mod.toTokens().toString()) {
                case "private" => isPrivate = true
                case "static" => isStatic = true
                case _ => ()
            }
        }
    }

    public func getJsonName(): String {
        if (let Some(v) <- jsonName) {
            return v
        } else {
            unwrapRawIdentifier(vd.identifier)
        }
    }
}
