package lsp_codegen

import stdx.serialization.serialization.*
import stdxx.IntegerOrString
import stdxx.serialization.*
import stdxx.deriving.*

/**
 * Mirrors https://microsoft.github.io/language-server-protocol/specifications/lsp/3.18/metaModel/metaModel.ts
 */
@DeriveExt[Serializable]
struct MetaModel {
    MetaModel(
        let metaData!: MetaData,
        let requests!: Array<Request>,
        let notifications!: Array<Notification>,
        let structures!: Array<Structure>,
        let enumerations!: Array<Enumeration>,
        let typeAliases!: Array<TypeAlias>
    ) {}
}

@DeriveExt[Serializable]
struct MetaData {
    MetaData(let version!: String) {}
}

@DeriveExt[Serializable]
@DeriveExtSerializable[skipNone]
struct Request {
    Request(
        let method!: String,
        let typeName!: ?String = None,
        let params!: ?OneOrMany<Type> = None,
        let result!: Type,
        let partialResult!: ?Type = None,
        let errorData!: ?Type = None,

        /**
         * Only when it differs from `method`.
         */
        let registrationMethod!: ?String = None,
        let registrationOptions!: ?Type = None,
        let messageDirection!: MessageDirection,
        let documentation!: ?String = None,
        let since!: ?String = None,
        let sinceTags!: ?Array<String> = None,
        let proposed!: ?Bool = None,
        let deprecated!: ?String = None,
        let clientCapability!: ?String = None,
        let serverCapability!: ?String = None
    ) {}
}

@DeriveExt[Serializable]
@DeriveExtSerializable[skipNone]
struct Notification {
    Notification(
        let method!: String,
        let typeName!: ?String = None,
        let params!: ?OneOrMany<Type> = None,

        /**
         * Only when it differs from `method`.
         */
        let registrationMethod!: ?String = None,
        let registrationOptions!: ?Type = None,
        let messageDirection!: MessageDirection,
        let documentation!: ?String = None,
        let since!: ?String = None,
        let sinceTags!: ?Array<String> = None,
        let proposed!: ?Bool = None,
        let deprecated!: ?String = None,
        let clientCapability!: ?String = None,
        let serverCapability!: ?String = None
    ) {}
}

@DeriveExt[Serializable]
@DeriveExtSerializable[skipNone]
struct Structure {
    Structure(
        let name!: String,
        let extends!: ?Array<Type> = None,
        let mixins!: ?Array<Type> = None,
        let properties!: Array<Property>,
        let documentation!: ?String = None,
        let since!: ?String = None,
        let sinceTags!: ?Array<String> = None,
        let proposed!: ?Bool = None,
        let deprecated!: ?String = None
    ) {}
}

@DeriveExt[Serializable]
@DeriveExtSerializable[skipNone]
struct Enumeration {
    Enumeration(
        let name!: String,
        @DeriveExtSerializable[rename: "type"] let enumerationType!: EnumerationType,
        let values!: Array<EnumerationEntry>,

        /**
         * Whether values outside `values` are allowed; absent means they are not.
         */
        let supportsCustomValues!: ?Bool = None,
        let documentation!: ?String = None,
        let since!: ?String = None,
        let sinceTags!: ?Array<String> = None,
        let proposed!: ?Bool = None,
        let deprecated!: ?String = None
    ) {}
}

@DeriveExt[Serializable]
@DeriveExtSerializable[skipNone]
struct TypeAlias {
    TypeAlias(
        let name!: String,
        @DeriveExtSerializable[rename: "type"] let typeAliasType!: Type,
        let documentation!: ?String = None,
        let since!: ?String = None,
        let sinceTags!: ?Array<String> = None,
        let proposed!: ?Bool = None,
        let deprecated!: ?String = None
    ) {}
}

@DeriveExt[Serializable]
enum BaseTypes {
    | @DeriveExtSerializable[value: "URI"]
    Uri
    | DocumentUri
    | @DeriveExtSerializable[value: "integer"]
    Integer
    | @DeriveExtSerializable[value: "uinteger"]
    UInteger
    | @DeriveExtSerializable[value: "decimal"]
    Decimal
    | RegExp
    | @DeriveExtSerializable[value: "string"]
    String
    | @DeriveExtSerializable[value: "boolean"]
    Boolean
    | @DeriveExtSerializable[value: "null"]
    Null
}

@DeriveExt[Serializable]
enum MessageDirection {
    | @DeriveExtSerializable[value: "clientToServer"]
    ClientToServer
    | @DeriveExtSerializable[value: "serverToClient"]
    ServerToClient
    | @DeriveExtSerializable[value: "both"]
    Both
}

@DeriveExt[Serializable]
enum MapKeyName {
    | @DeriveExtSerializable[value: "URI"]
    Uri
    | DocumentUri
    | @DeriveExtSerializable[value: "string"]
    String
    | @DeriveExtSerializable[value: "integer"]
    Integer
}

/**
 * A reference here resolves to a `string` or an `integer`: `ChangeAnnotationIdentifier`.
 */
@DeriveExt[Serializable]
@DeriveExtSerializable[tag: "kind"]
enum MapKeyType {
    | @DeriveExtSerializable[value: "base", payload: ["name"]]
    Base(MapKeyName)
    | @DeriveExtSerializable[value: "reference", payload: ["name"]]
    Reference(String)
}

@DeriveExt[Serializable]
@DeriveExtSerializable[tag: "kind"]
enum Type {
    | @DeriveExtSerializable[value: "base", payload: ["name"]]
    Base(BaseTypes)

    /**
     * To a `Structure`, an `Enumeration` or a `TypeAlias` of the same meta model.
     */
    | @DeriveExtSerializable[value: "reference", payload: ["name"]]
    Reference(String)

    | @DeriveExtSerializable[value: "array", payload: ["element"]]
    Array(Type)

    | @DeriveExtSerializable[value: "map", payload: ["key", "value"]]
    Map(MapKeyType, Type)

    | @DeriveExtSerializable[value: "and", payload: ["items"]]
    And(Array<Type>)

    | @DeriveExtSerializable[value: "or", payload: ["items"]]
    Or(Array<Type>)

    | @DeriveExtSerializable[value: "tuple", payload: ["items"]]
    Tuple(Array<Type>)

    /**
     * An anonymous structure: `property: { start: uinteger; end: uinteger; }`.
     */
    | @DeriveExtSerializable[value: "literal", payload: ["value"]]
    Literal(StructureLiteral)

    | @DeriveExtSerializable[value: "stringLiteral", payload: ["value"]]
    StringLiteral(String)

    | @DeriveExtSerializable[value: "integerLiteral", payload: ["value"]]
    IntegerLiteral(Int64)

    | @DeriveExtSerializable[value: "booleanLiteral", payload: ["value"]]
    BooleanLiteral(Bool)
}

@DeriveExt[Serializable]
@DeriveExtSerializable[skipNone]
struct StructureLiteral {
    StructureLiteral(
        let properties!: Array<Property>,
        let documentation!: ?String = None,
        let since!: ?String = None,
        let sinceTags!: ?Array<String> = None,
        let proposed!: ?Bool = None,
        let deprecated!: ?String = None
    ) {}
}

@DeriveExt[Serializable]
@DeriveExtSerializable[skipNone]
struct Property {
    Property(
        let name!: String,
        @DeriveExtSerializable[rename: "type"] let propertyType!: Type,
        let optional!: ?Bool = None,
        let documentation!: ?String = None,
        let since!: ?String = None,
        let sinceTags!: ?Array<String> = None,
        let proposed!: ?Bool = None,
        let deprecated!: ?String = None
    ) {}
}

@DeriveExt[Serializable]
enum OneOrMany<T> {
    | One(T)
    | Many(Array<T>)
}

@DeriveExt[Serializable]
@DeriveExtSerializable[skipNone]
struct EnumerationEntry {
    EnumerationEntry(
        let name!: String,
        let value!: IntegerOrString,
        let documentation!: ?String = None,
        let since!: ?String = None,
        let sinceTags!: ?Array<String> = None,
        let proposed!: ?Bool = None,
        let deprecated!: ?String = None
    ) {}
}

@DeriveExt[Serializable]
@DeriveExtSerializable[tag: "kind", value: "base"]
struct EnumerationType {
    EnumerationType(let name!: EnumerationBaseType) {}
}

@DeriveExt[Serializable]
enum EnumerationBaseType {
    | @DeriveExtSerializable[value: "string"]
    String
    | @DeriveExtSerializable[value: "integer"]
    Integer
    | @DeriveExtSerializable[value: "uinteger"]
    UInteger
}
