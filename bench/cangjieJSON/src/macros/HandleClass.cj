/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2024-2025. All rights reserved.
 */
macro package cjjson.macros

import std.ast.*
import std.collection.*

class HandleClass {
    private let cd: ClassDecl
    private var className: Tokens
    private let allFields = ArrayList<FieldInfo>()

    private var withSuperClass: Bool = false
    private var superClass: Tokens = Tokens()
    private var withGenericType: Bool = false
    private var genericType: Tokens = Tokens()
    private var allowNull: Bool = false

    private var isOpen: Bool = false // 表示是否是一个 open 的 class

    public init(cd: ClassDecl) {
        this.cd = cd

        this.className = if (this.cd.isGenericDecl) {
            this.cd.identifier.toTokens() + this.cd.genericParam.toTokens()
        } else {
            this.cd.identifier.toTokens()
        }

        for (item in cd.modifiers) {
            if (item.toTokens().toString() == "open") {
                this.isOpen = true
                break
            }
        }
    }

    private func handleSuperTypes() {
        let refType = RefType(quote(IJsonAdapter<$(className)>))
        var hasAdded = false
        for (item in cd.superTypes) {
            if (item.toTokens().toString() == refType.toTokens().toString()) {
                hasAdded = true
                break
            }
        }
        if (!hasAdded) {
            cd.superTypes.add(refType)
        }
    }

    private func fromJsonValueFunc(): FuncDecl {
        var funcBody = Tokens()

        if (withSuperClass) {
            funcBody.append(quote(
                $superClass.fromJsonValueInherit(jsonObj, obj)
            ))
        }

        for (field in allFields) {
            if (field.isIgnore) {
                continue
            }
            let identifier = field.vd.identifier
            let jsonName = field.getJsonName()
            let typeInfo = field.vd.declType

            let assignExpr = if (isOptionType(typeInfo)) {
                let baseType = getOptionBaseType(typeInfo)
                quote(
                    obj.$identifier = Option<$baseType>.fromJsonValue(jsonObj.get($jsonName) ?? JsonNull())
                )
            } else {
                quote(
                    obj.$identifier = $typeInfo.fromJsonValue(jsonObj.get($jsonName).getOrThrow({=> JsonFieldNotExist($(this.className.toString()), $jsonName)}))
                )
            }

            let expr = if (this.allowNull || field.useDefault) {
                // 如果该 class 标记了 allowNull，或者该成员标记了 @JsonDefault，则仅当 json 字符串中包含该字段时，才对成员变量进行解析赋值，否则保持默认值。
                quote(
                    if (jsonObj.containsKey($jsonName) && jsonObj.get($jsonName).getOrThrow().toString() != "null") {
                        $assignExpr
                    }
                )
            } else {
                quote(
                    try {
                        $assignExpr
                    } catch (e: JsonTypeMismatch) {
                        throw JsonTypeMismatch($(this.className.toString()), $jsonName, e.message)
                    }
                )
            }

            funcBody.append(expr)
        }

        return FuncDecl(
            quote(
            public static func fromJsonValue(jsonValue: JsonValue): $className {
                let jsonObj = match (jsonValue) {
                    case obj: JsonObject => obj
                    case _ => throw JsonTypeMismatch("JSON Object", jsonValue.kind().toString())
                }

                let obj = $className()

                $funcBody
                return obj
            }
        ))
    }

    private func fromJsonFunc(): FuncDecl {
        return FuncDecl(
            quote(
            public static func fromJson(str: String): $className {
                return fromJsonValue(JsonValue.fromStr(str))
            }
        ))
    }

    private func toJsonValueFunc(): FuncDecl {
        var funcBody = Tokens()

        if (withSuperClass) {
            funcBody.append(quote(
                super.toJsonValueInherit(jsonObj)
            ))
        }

        for (field in allFields) {
            if (field.isIgnore) {
                continue
            }
            let jsonName = field.getJsonName()
            if (field.isIgnoreNull && isOptionType(field.vd.declType)) {
                funcBody.append(
                    quote(
                    if (let Some(v) <- $(field.vd.identifier)) {
                        jsonObj.put($(jsonName), $(field.vd.identifier).toJsonValue())
                    }
                ))
            } else {
                funcBody.append(
                    quote(
                    jsonObj.put($(jsonName), $(field.vd.identifier).toJsonValue())
                ))
            }
        }

        let openModifier = if (isOpen) {
            quote(open)
        } else {
            quote()
        }

        return FuncDecl(
            quote(
            public $openModifier func toJsonValue(): JsonValue {
                let jsonObj = JsonObject()
                $funcBody
                return jsonObj

            }
        ))
    }

    private func toJsonFunc(): FuncDecl {
        let openModifier = if (isOpen) {
            quote(open)
        } else {
            quote()
        }

        return FuncDecl(
            quote(
            public $openModifier func toJson(): String {
                return toJsonValue().toString()
            }
        ))
    }

    private func fromJsonValueInheritFunc(): FuncDecl {
        var funcBody = Tokens()

        if (withSuperClass) {
            funcBody.append(quote(
                $superClass.fromJsonValueInherit(jsonValue, obj)
            ))
        }

        for (field in allFields) {
            if (field.isIgnore) {
                continue
            }
            let identifier = field.vd.identifier
            let jsonName = field.getJsonName()
            let typeInfo = field.vd.declType

            let assignExpr = if (isOptionType(typeInfo)) {
                let baseType = getOptionBaseType(typeInfo)
                quote(
                    obj.$identifier = Option<$baseType>.fromJsonValue(jsonObj.get($jsonName) ?? JsonNull())
                )
            } else {
                quote(
                    obj.$identifier = $typeInfo.fromJsonValue(jsonObj.get($jsonName).getOrThrow({=> JsonFieldNotExist($(this.className.toString()), $jsonName)}))
                )
            }

            let expr = if (this.allowNull || field.useDefault) {
                // 如果该 class 标记了 allowNull，或者该成员标记了 @JsonDefault，则仅当 json 字符串中包含该字段时，才对成员变量进行解析赋值，否则保持默认值。
                quote(
                    if (jsonObj.containsKey($jsonName) && jsonObj.get($jsonName).getOrThrow().toString() != "null") {
                        $assignExpr
                    }
                )
            } else {
                quote(
                    try {
                        $assignExpr
                    } catch (e: JsonTypeMismatch) {
                        throw JsonTypeMismatch($(this.className.toString()), $jsonName, e.message)
                    }
                )
            }

            funcBody.append(expr)
        }

        return FuncDecl(
            quote(
            public static func fromJsonValueInherit(jsonValue: JsonValue, obj: $className): Unit {
                let jsonObj = jsonValue.asObject()
                $funcBody
            }
        ))
    }

    private func toJsonValueInheritFunc(): FuncDecl {
        var funcBody = Tokens()

        if (withSuperClass) {
            funcBody.append(quote(
                super.toJsonValueInherit(jsonValue)
            ))
        }

        for (field in allFields) {
            if (field.isIgnore) {
                continue
            }
            let jsonName = field.getJsonName()
            if (field.isIgnoreNull && isOptionType(field.vd.declType)) {
                funcBody.append(
                    quote(
                    if (let Some(v) <- $(field.vd.identifier)) {
                        jsonObj.put($(jsonName), $(field.vd.identifier).toJsonValue())
                    }
                ))
            } else {
                funcBody.append(
                    quote(
                    jsonObj.put($(jsonName), $(field.vd.identifier).toJsonValue())
                ))
            }
        }

        let openModifier = if (isOpen) {
            quote(open)
        } else {
            quote()
        }

        return FuncDecl(
            quote(
            public $openModifier func toJsonValueInherit(jsonValue: JsonValue): Unit {
                let jsonObj = jsonValue.asObject()
                $funcBody
            }
        ))
    }

    private func handleAttr(attr: Tokens): Unit {
        if (attr.size == 0) {
            return
        }
        var offset: Int64 = 0
        while (offset < attr.size) {
            try {
                let (expr, off) = parseExprFragment(attr, startFrom: offset)
                match (expr) {
                    case ae: AssignExpr =>
                        let key = ae.leftExpr.toTokens().toString()
                        let value = ae.rightExpr
                        if (key == JsonAdapterClassAttr.WITH_SUPER_CLASS) {
                            this.withSuperClass = true
                            this.superClass = value.toTokens()
                        } else if (key == JsonAdapterClassAttr.WITH_GENERIC_TYPE) {
                            if (value.toTokens().size != 1) {
                                diagReport(DiagReportLevel.ERROR, value.toTokens(), "only one generic type is allowed",
                                    "only one generic type is allowed")
                            }
                            this.withGenericType = true
                            this.genericType = value.toTokens()
                        } else {
                            diagReport(DiagReportLevel.ERROR, ae.toTokens(),
                                "Unknown key, it should be one of ${JsonAdapterClassAttr.availableAttrs()}",
                                "Unknown key, it should be one of ${JsonAdapterClassAttr.availableAttrs()}")
                        }
                    case re: RefExpr =>
                        let key = re.identifier.value
                        if (key == JsonAdapterClassAttr.ALLOW_NULL) {
                            this.allowNull = true
                        } else {
                            diagReport(DiagReportLevel.ERROR, re.toTokens(),
                                "Unknown key, it should be one of ${JsonAdapterClassAttr.availableAttrs()}",
                                "Unknown key, it should be one of ${JsonAdapterClassAttr.availableAttrs()}")
                        }
                    case _ => diagReport(DiagReportLevel.ERROR, expr.toTokens(),
                        "expect AssignExpr, and key should be one of ${JsonAdapterClassAttr.availableAttrs()}",
                        "expect AssignExpr, and key should be one of ${JsonAdapterClassAttr.availableAttrs()}")
                }
                offset = off
            } catch (e: ParseASTException) {
                diagReport(DiagReportLevel.ERROR, attr,
                    "attributes is illegal, it should looks like [${JsonAdapterClassAttr.WITH_SUPER_CLASS} = Xxx; ${JsonAdapterClassAttr.WITH_GENERIC_TYPE} = T]",
                    "attributes is illegal")
                break
            }
        }
    }

    // 检查泛型变元是否一致，并且为泛型变元增加接口约束。
    private func handleGenericType(): Unit {
        if (!withGenericType) {
            return
        }

        if (!this.cd.isGenericDecl) {
            diagReport(DiagReportLevel.ERROR, this.cd.identifier.toTokens(),
                "expect to be a generic class type when using `${JsonAdapterClassAttr.WITH_GENERIC_TYPE}` attribute",
                "expect to be a generic class")
            return
        }

        let gpTokens = this.cd.genericParam.parameters.toTokens()
        if (gpTokens.size != 1) {
            diagReport(DiagReportLevel.ERROR, gpTokens, "can only have one generic param",
                "can only have one generic param")
            return
        }

        let gp = gpTokens.get(0)
        if (gp.toTokens().toString() != genericType.toString()) {
            diagReport(DiagReportLevel.ERROR, gpTokens,
                "generic param is inconsistent with `${JsonAdapterClassAttr.WITH_GENERIC_TYPE}` attribute",
                "generic param is inconsistent with `${JsonAdapterClassAttr.WITH_GENERIC_TYPE}` attribute")
            return
        }

        let gcList = this.cd.genericConstraint
        let gc = GenericConstraint()
        gc.keyword = Token(TokenKind.WHERE)
        gc.typeArgument = RefType(genericType)
        gc.upperBounds.add(RefType(quote(IJsonAdapter<T>)))

        if (gcList.size == 0) {
            this.cd.genericConstraint.add(gc)
        } else {
            var hasAdd = false
            for (item in gcList) {
                let ta = item.typeArgument
                if (ta.toTokens().toString() == genericType.toString()) {
                    for (value in item.upperBounds) {
                        match (value) {
                            case rt: RefType =>
                                if (rt.identifier.toTokens().toString() == "IJsonAdapter") {
                                    hasAdd = true
                                    break
                                }
                            case _ => ()
                        }
                    }
                    if (!hasAdd) {
                        item.upperBounds.add(RefType(quote(IJsonAdapter<T>)))
                        hasAdd = true
                    }
                }
            }
            if (!hasAdd) {
                this.cd.genericConstraint.add(gc)
            }
        }
    }

    public func doExpend(attr: Tokens): Tokens {
        handleAttr(attr)

        handleGenericType()

        handleSuperTypes()

        // collect all fields
        for (decl in cd.body.decls) {
            match (decl) {
                case vd: VarDecl =>
                    let field = FieldInfo(vd)
                    if (field.isStatic && !field.isIgnore) {
                        diagReport(DiagReportLevel.ERROR, vd.toTokens(), "`static` member variable must use @JsonIgnore",
                            "must use @JsonIgnore")
                    }
                    this.allFields.add(field)
                case _ => ()
            }
        }

        cd.body.decls.add(fromJsonFunc())
        cd.body.decls.add(toJsonFunc())
        cd.body.decls.add(fromJsonValueFunc())
        cd.body.decls.add(toJsonValueFunc())

        // 只有在有可能被继承的情况下，才需要生成这2个方法，用于子类调用父类的对应方法。
        if (this.isOpen) {
            cd.body.decls.add(fromJsonValueInheritFunc())
            cd.body.decls.add(toJsonValueInheritFunc())
        }

        return cd.toTokens()
    }
}
