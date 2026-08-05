package lsp_codegen

import stdx.serialization.serialization.*
import stdxx.*

/**
 * The actual meta model.
 * @note specification taken from: https://microsoft.github.io/language-server-protocol/specifications/lsp/3.18/metaModel/metaModel.ts
 */
struct MetaModel <: Serializable<MetaModel> {
    MetaModel(
        /**
         * Additional meta data.
         */
        let metaData!: MetaData,

        /**
         * The requests.
         */
        let requests!: Array<Request>,

        /**
         * The notifications.
         */
        let notifications!: Array<Notification>,

        /**
         * The structures.
         */
        let structures!: Array<Structure>,

        /**
         * The enumerations.
         */
        let enumerations!: Array<Enumeration>,

        /**
         * The type aliases.
         */
        let typeAliases!: Array<TypeAlias>
    ) {}

    /**
     * @throws DataModelException - if unable to deserialize DataModel
     */
    public static func deserialize(dm: DataModel): MetaModel {
        let dms = match (dm) {
            case dms: DataModelStruct => dms
            case _ => throw DataModelException("expected `DataModelStruct`")
        }

        MetaModel(
            metaData: dms.getDeserializedOrThrow("metaData"),
            requests: dms.getDeserializedOrThrow("requests"),
            notifications: dms.getDeserializedOrThrow("notifications"),
            structures: dms.getDeserializedOrThrow("structures"),
            enumerations: dms.getDeserializedOrThrow("enumerations"),
            typeAliases: dms.getDeserializedOrThrow("typeAliases")
        )
    }

    public func serialize(): DataModel {
        DataModelStruct()
            .add(field("metaData", metaData))
            .add(field("requests", requests))
            .add(field("notifications", notifications))
            .add(field("structures", structures))
            .add(field("enumerations", enumerations))
            .add(field("typeAliases", typeAliases))
    }
}

struct MetaData <: Serializable<MetaData> {
    MetaData(
        /**
         * The protocol version.
         */
        let version!: String) {}

    /**
     * @throws DataModelException - if unable to deserialize DataModel
     */
    public static func deserialize(dm: DataModel): MetaData {
        let dms = match (dm) {
            case dms: DataModelStruct => dms
            case _ => throw DataModelException("expected `DataModelStruct`")
        }

        MetaData(version: dms.getDeserializedOrThrow("version"))
    }

    public func serialize(): DataModel {
        DataModelStruct().add(field("version", version))
    }
}

/**
 * Represents a LSP request
 */
struct Request <: Serializable<Request> {
    Request(
        /**
         * The request's method name.
         */
        let method!: String,

        /**
         * The type name of the request if any.
         */
        let typeName!: ?String = None,

        /**
         * The parameter type(s) if any.
         */
        let params!: ?OneOrMany<Type> = None,

        /**
         * The result type.
         */
        let result!: Type,

        /**
         * Optional partial result type if the request
         * supports partial result reporting.
         */
        let partialResult!: ?Type = None,

        /**
         * An optional error data type.
         */
        let errorData!: ?Type = None,

        /**
         * Optional a dynamic registration method if it
         * different from the request's method.
         */
        let registrationMethod!: ?String = None,

        /**
         * Optional registration options if the request
         * supports dynamic registration.
         */
        let registrationOptions!: ?Type = None,

        /**
         * The direction in which this request is sent
         * in the protocol.
         */
        let messageDirection!: MessageDirection,

        /**
         * An optional documentation.
         */
        let documentation!: ?String = None,

        /**
         * Since when (release number) this property is
         * available. Is None if not known.
         */
        let since!: ?String = None,

        /**
         * All since tags in case there was more than one tag.
         * Is None if not known.
         */
        let sinceTags!: ?Array<String> = None,

        /**
         * Whether this is a proposed property. If omitted,
         * the structure is final.
         */
        let proposed!: Bool = false,

        /**
         * Whether the property is deprecated or not. If deprecated
         * the property contains the deprecation message.
         */
        let deprecated!: ?String = None,

        /**
         * The client capability property path if any.
         */
        let clientCapability!: ?String = None,

        /**
         * The server capability property path if any.
         */
        let serverCapability!: ?String = None
    ) {}

    /**
     * @throws DataModelException - if unable to deserialize DataModel
     */
    public static func deserialize(dm: DataModel): Request {
        let dms = match (dm) {
            case dms: DataModelStruct => dms
            case _ => throw DataModelException("expected `DataModelStruct`")
        }

        Request(
            method: dms.getDeserializedOrThrow("method"),
            typeName: dms.getDeserializedOrNone("typeName"),
            params: dms.getDeserializedOrNone("params"),
            result: dms.getDeserializedOrThrow("result"),
            partialResult: dms.getDeserializedOrNone("partialResult"),
            errorData: dms.getDeserializedOrNone("errorData"),
            registrationMethod: dms.getDeserializedOrNone("registrationMethod"),
            registrationOptions: dms.getDeserializedOrNone("registrationOptions"),
            messageDirection: dms.getDeserializedOrThrow("messageDirection"),
            documentation: dms.getDeserializedOrNone("documentation"),
            since: dms.getDeserializedOrNone("since"),
            sinceTags: dms.getDeserializedOrNone("sinceTags"),
            proposed: dms.getDeserializedOrNone<Bool>("proposed") ?? false,
            deprecated: dms.getDeserializedOrNone("deprecated"),
            clientCapability: dms.getDeserializedOrNone("clientCapability"),
            serverCapability: dms.getDeserializedOrNone("serverCapability"),
        )
    }

    public func serialize(): DataModel {
        let dms = DataModelStruct()
            .add(field("method", method))
            .add(field("result", result))
            .add(field("messageDirection", messageDirection))
            .add(field("proposed", proposed))

        dms.addFieldIfSome("typeName", typeName)
        dms.addFieldIfSome("params", params)
        dms.addFieldIfSome("partialResult", partialResult)
        dms.addFieldIfSome("errorData", errorData)
        dms.addFieldIfSome("registrationMethod", registrationMethod)
        dms.addFieldIfSome("registrationOptions", registrationOptions)
        dms.addFieldIfSome("documentation", documentation)
        dms.addFieldIfSome("since", since)
        dms.addFieldIfSome("sinceTags", sinceTags)
        dms.addFieldIfSome("deprecated", deprecated)
        dms.addFieldIfSome("clientCapability", clientCapability)
        dms.addFieldIfSome("serverCapability", serverCapability)

        dms
    }
}

/**
 * Represents a LSP notification
 */
struct Notification <: Serializable<Notification> {
    Notification(
        /**
         * The notifications's method name.
         */
        let method!: String,

        /**
         * The type name of the notifications if any.
         */
        let typeName!: ?String = None,

        /**
         * The parameter type(s) if any.
         */
        let params!: ?OneOrMany<Type> = None,

        /**
         * Optional a dynamic registration method if it
         * different from the notifications's method.
         */
        let registrationMethod!: ?String = None,

        /**
         * Optional registration options if the notification
         * supports dynamic registration.
         */
        let registrationOptions!: ?Type = None,

        /**
         * The direction in which this notification is sent
         * in the protocol.
         */
        let messageDirection!: MessageDirection,

        /**
         * An optional documentation.
         */
        let documentation!: ?String = None,

        /**
         * Since when (release number) this property is
         * available. Is None if not known.
         */
        let since!: ?String = None,

        /**
         * All since tags in case there was more than one tag.
         * Is None if not known.
         */
        let sinceTags!: ?Array<String> = None,

        /**
         * Whether this is a proposed property. If omitted,
         * the structure is final.
         */
        let proposed!: Bool = false,

        /**
         * Whether the property is deprecated or not. If deprecated
         * the property contains the deprecation message.
         */
        let deprecated!: ?String = None,

        /**
         * The client capability property path if any.
         */
        let clientCapability!: ?String = None,

        /**
         * The server capability property path if any.
         */
        let serverCapability!: ?String = None
    ) {}

    /**
     * @throws DataModelException - if unable to deserialize DataModel
     */
    public static func deserialize(dm: DataModel): Notification {
        let dms = match (dm) {
            case dms: DataModelStruct => dms
            case _ => throw DataModelException("expected `DataModelStruct`")
        }

        Notification(
            method: dms.getDeserializedOrThrow("method"),
            typeName: dms.getDeserializedOrNone("typeName"),
            params: dms.getDeserializedOrNone("params"),
            registrationMethod: dms.getDeserializedOrNone("registrationMethod"),
            registrationOptions: dms.getDeserializedOrNone("registrationOptions"),
            messageDirection: dms.getDeserializedOrThrow("messageDirection"),
            documentation: dms.getDeserializedOrNone("documentation"),
            since: dms.getDeserializedOrNone("since"),
            sinceTags: dms.getDeserializedOrNone("sinceTags"),
            proposed: dms.getDeserializedOrNone<Bool>("proposed") ?? false,
            deprecated: dms.getDeserializedOrNone("deprecated"),
            clientCapability: dms.getDeserializedOrNone("clientCapability"),
            serverCapability: dms.getDeserializedOrNone("serverCapability"),
        )
    }

    public func serialize(): DataModel {
        let dms = DataModelStruct()
            .add(field("method", method))
            .add(field("messageDirection", messageDirection))
            .add(field("proposed", proposed))

        dms.addFieldIfSome("typeName", typeName)
        dms.addFieldIfSome("params", params)
        dms.addFieldIfSome("registrationMethod", registrationMethod)
        dms.addFieldIfSome("registrationOptions", registrationOptions)
        dms.addFieldIfSome("documentation", documentation)
        dms.addFieldIfSome("since", since)
        dms.addFieldIfSome("sinceTags", sinceTags)
        dms.addFieldIfSome("deprecated", deprecated)
        dms.addFieldIfSome("clientCapability", clientCapability)
        dms.addFieldIfSome("serverCapability", serverCapability)

        dms
    }
}

/**
 * Defines the structure of an object literal.
 */
struct Structure <: Serializable<Structure> {
    Structure(
        /**
         * The name of the structure.
         */
        let name!: String,

        /**
         * Structures extended from. This structures form
         * a polymorphic type hierarchy.
         */
        let extends!: ?Array<Type> = None,

        /**
         * Structures to mix in. The properties of these
         * structures are `copied` into this structure.
         * Mixins don't form a polymorphic type hierarchy in
         * LSP.
         */
        let mixins!: ?Array<Type> = None,

        /**
         * The properties.
         */
        let properties!: Array<Property>,

        /**
         * An optional documentation.
         */
        let documentation!: ?String = None,

        /**
         * Since when (release number) this property is
         * available. Is None if not known.
         */
        let since!: ?String = None,

        /**
         * All since tags in case there was more than one tag.
         * Is None if not known.
         */
        let sinceTags!: ?Array<String> = None,

        /**
         * Whether this is a proposed property. If omitted,
         * the structure is final.
         */
        let proposed!: Bool = false,

        /**
         * Whether the property is deprecated or not. If deprecated
         * the property contains the deprecation message.
         */
        let deprecated!: ?String = None
    ) {}

    /**
     * @throws DataModelException - if unable to deserialize DataModel
     */
    public static func deserialize(dm: DataModel): Structure {
        let dms = match (dm) {
            case dms: DataModelStruct => dms
            case _ => throw DataModelException("expected `DataModelStruct`")
        }

        Structure(
            name: dms.getDeserializedOrThrow("name"),
            extends: dms.getDeserializedOrNone("extends"),
            mixins: dms.getDeserializedOrNone("mixins"),
            properties: dms.getDeserializedOrThrow("properties"),
            documentation: dms.getDeserializedOrNone("documentation"),
            since: dms.getDeserializedOrNone("since"),
            sinceTags: dms.getDeserializedOrNone("sinceTags"),
            proposed: dms.getDeserializedOrNone<Bool>("proposed") ?? false,
            deprecated: dms.getDeserializedOrNone("deprecated"),
        )
    }

    public func serialize(): DataModel {
        let dms = DataModelStruct()
            .add(field("name", name))
            .add(field("properties", properties))
            .add(field("proposed", proposed))

        dms.addFieldIfSome("extends", extends)
        dms.addFieldIfSome("mixins", mixins)
        dms.addFieldIfSome("documentation", documentation)
        dms.addFieldIfSome("since", since)
        dms.addFieldIfSome("sinceTags", sinceTags)
        dms.addFieldIfSome("deprecated", deprecated)

        dms
    }
}

/**
 * Defines an enumeration.
 */
struct Enumeration <: Serializable<Enumeration> {
    Enumeration(
        /**
         * The name of the enumeration.
         */
        let name!: String,

        /**
         * The type of the elements.
         */
        let `type`!: EnumerationType,

        /**
         * The enum values.
         */
        let values!: Array<EnumerationEntry>,

        /**
         * Whether the enumeration supports custom values (e.g. values which are not
         * part of the set defined in `values`). If omitted no custom values are
         * supported.
         */
        let supportsCustomValues!: Bool = false,

        /**
         * An optional documentation.
         */
        let documentation!: ?String = None,

        /**
         * Since when (release number) this property is
         * available. Is None if not known.
         */
        let since!: ?String = None,

        /**
         * All since tags in case there was more than one tag.
         * Is None if not known.
         */
        let sinceTags!: ?Array<String> = None,

        /**
         * Whether this is a proposed property. If omitted,
         * the structure is final.
         */
        let proposed!: Bool = false,

        /**
         * Whether the property is deprecated or not. If deprecated
         * the property contains the deprecation message.
         */
        let deprecated!: ?String = None
    ) {}

    /**
     * @throws DataModelException - if unable to deserialize DataModel
     */
    public static func deserialize(dm: DataModel): Enumeration {
        let dms = match (dm) {
            case dms: DataModelStruct => dms
            case _ => throw DataModelException("expected `DataModelStruct`")
        }

        Enumeration(
            name: dms.getDeserializedOrThrow("name"),
            `type`: dms.getDeserializedOrThrow("type"),
            values: dms.getDeserializedOrThrow("values"),
            supportsCustomValues: dms.getDeserializedOrNone<Bool>("supportsCustomValues") ?? false,
            documentation: dms.getDeserializedOrNone("documentation"),
            since: dms.getDeserializedOrNone("since"),
            sinceTags: dms.getDeserializedOrNone("sinceTags"),
            proposed: dms.getDeserializedOrNone<Bool>("proposed") ?? false,
            deprecated: dms.getDeserializedOrNone("deprecated"),
        )
    }

    public func serialize(): DataModel {
        let dms = DataModelStruct()
            .add(field("name", name))
            .add(field("type", `type`))
            .add(field("values", values))
            .add(field("supportsCustomValues", supportsCustomValues))
            .add(field("proposed", proposed))

        dms.addFieldIfSome("documentation", documentation)
        dms.addFieldIfSome("since", since)
        dms.addFieldIfSome("sinceTags", sinceTags)
        dms.addFieldIfSome("deprecated", deprecated)

        dms
    }
}

/**
 * Defines a type alias.
 * (e.g. `type Definition = Location | LocationLink`)
 */
struct TypeAlias <: Serializable<TypeAlias> {
    TypeAlias(
        /**
         * The name of the type alias.
         */
        let name!: String,

        /**
         * The aliased type.
         */
        let `type`!: Type,

        /**
         * An optional documentation.
         */
        let documentation!: ?String = None,

        /**
         * Since when (release number) this property is
         * available. Is None if not known.
         */
        let since!: ?String = None,

        /**
         * All since tags in case there was more than one tag.
         * Is None if not known.
         */
        let sinceTags!: ?Array<String> = None,

        /**
         * Whether this is a proposed property. If omitted,
         * the structure is final.
         */
        let proposed!: Bool = false,

        /**
         * Whether the property is deprecated or not. If deprecated
         * the property contains the deprecation message.
         */
        let deprecated!: ?String = None
    ) {}

    /**
     * @throws DataModelException - if unable to deserialize DataModel
     */
    public static func deserialize(dm: DataModel): TypeAlias {
        let dms = match (dm) {
            case dms: DataModelStruct => dms
            case _ => throw DataModelException("expected `DataModelStruct`")
        }

        TypeAlias(
            name: dms.getDeserializedOrThrow("name"),
            `type`: dms.getDeserializedOrThrow("type"),
            documentation: dms.getDeserializedOrNone("documentation"),
            since: dms.getDeserializedOrNone("since"),
            sinceTags: dms.getDeserializedOrNone("sinceTags"),
            proposed: dms.getDeserializedOrNone<Bool>("proposed") ?? false,
            deprecated: dms.getDeserializedOrNone("deprecated"),
        )
    }

    public func serialize(): DataModel {
        let dms = DataModelStruct().add(field("name", name)).add(field("type", `type`)).add(field("proposed", proposed))

        dms.addFieldIfSome("documentation", documentation)
        dms.addFieldIfSome("since", since)
        dms.addFieldIfSome("sinceTags", sinceTags)
        dms.addFieldIfSome("deprecated", deprecated)

        dms
    }
}

enum BaseTypes <: Serializable<BaseTypes> {
    // URI
    | Uri
    | DocumentUri
    // integer
    | Integer
    // uinteger
    | UInteger
    // decimal
    | Decimal
    | RegExp
    // string
    | String
    // boolean
    | Boolean
    // null
    | Null

    /**
     * @throws DataModelException - if unable to deserialize DataModel
     */
    public static func deserialize(dm: DataModel): BaseTypes {
        let dmStr = match (dm) {
            case dmStr: DataModelString => dmStr
            case _ => throw DataModelException("expected `DataModelString`")
        }

        match (dmStr.getValue()) {
            case "URI" => Uri
            case "DocumentUri" => DocumentUri
            case "integer" => Integer
            case "uinteger" => UInteger
            case "decimal" => Decimal
            case "RegExp" => RegExp
            case "string" => String
            case "boolean" => Boolean
            case "null" => Null
            case _ => throw DataModelException("invalid `BaseTypes` value")
        }
    }

    public func serialize(): DataModel {
        DataModelString(match (this) {
            case Uri => "URI"
            case DocumentUri => "DocumentUri"
            case Integer => "integer"
            case UInteger => "uinteger"
            case Decimal => "decimal"
            case RegExp => "RegExp"
            case String => "string"
            case Boolean => "boolean"
            case Null => "null"
        })
    }
}

/**
 * Indicates in which direction a message is sent in the protocol.
 */
enum MessageDirection <: Serializable<MessageDirection> {
    // clientToServer
    | ClientToServer
    // serverToClient
    | ServerToClient
    // both
    | Both

    /**
     * @throws DataModelException - if unable to deserialize DataModel
     */
    public static func deserialize(dm: DataModel): MessageDirection {
        let dmStr = match (dm) {
            case dmStr: DataModelString => dmStr
            case _ => throw DataModelException("expected `DataModelString`")
        }

        match (dmStr.getValue()) {
            case "clientToServer" => ClientToServer
            case "serverToClient" => ServerToClient
            case "both" => Both
            case _ => throw DataModelException("invalid `MessageDirection` value")
        }
    }

    public func serialize(): DataModel {
        DataModelString(match (this) {
            case ClientToServer => "clientToServer"
            case ServerToClient => "serverToClient"
            case Both => "both"
        })
    }
}

enum MapKeyName <: Serializable<MapKeyName> {
    // URI
    | Uri
    | DocumentUri
    // stringø
    | String
    // integer
    | Integer

    /**
     * @throws DataModelException - if unable to deserialize DataModel
     */
    public static func deserialize(dm: DataModel): MapKeyName {
        let dmStr = match (dm) {
            case dmStr: DataModelString => dmStr
            case _ => throw DataModelException("expected `DataModelString`")
        }

        match (dmStr.getValue()) {
            case "URI" => Uri
            case "DocumentUri" => DocumentUri
            case "string" => String
            case "integer" => Integer
            case _ => throw DataModelException("invalid `MapKeyName` value")
        }
    }

    public func serialize(): DataModel {
        DataModelString(match (this) {
            case Uri => "URI"
            case DocumentUri => "DocumentUri"
            case String => "string"
            case Integer => "integer"
        })
    }
}

/**
 * Represents a type that can be used as a key in a
 * map type. If a reference type is used then the
 * type must either resolve to a `string` or `integer`
 * type. (e.g. `type ChangeAnnotationIdentifier === string`).
 */
enum MapKeyType <: Serializable<MapKeyType> {
    | Base(MapKeyName)
    | Reference(String)

    /**
     * @throws DataModelException - if unable to deserialize DataModel
     */
    public static func deserialize(dm: DataModel): MapKeyType {
        let dms = match (dm) {
            case dms: DataModelStruct => dms
            case _ => throw DataModelException("expected `DataModelStruct`")
        }

        match (dms.getDeserializedOrThrow<String>("kind")) {
            case "base" => Base(dms.getDeserializedOrThrow("name"))
            case "reference" => Reference(dms.getDeserializedOrThrow("name"))
            case kind => throw DataModelException("unexpected `kind` field value: \"${kind}\"")
        }
    }

    public func serialize(): DataModel {
        match (this) {
            case Base(name) => DataModelStruct().add(field("kind", "base")).add(field("name", name))
            case Reference(ref) => DataModelStruct().add(field("kind", "reference")).add(field("name", ref))
        }
    }
}

enum Type <: Serializable<Type> {
    /**
     * Represents a base type like `string` or `DocumentUri`.
     */
    | Base( /* name */ BaseTypes)

    /**
     * Represents a reference to another type (e.g. `TextDocument`).
     * This is either a `Structure`, a `Enumeration` or a `TypeAlias`
     * in the same meta model.
     */
    | Reference( /* name */ String)

    /**
     * Represents an array type (e.g. `TextDocument[]`).
     */
    | Array( /* element */ Type)

    /**
     * Represents a JSON object map
     * (e.g. `interface Map<K extends string | integer, V> { [key: K] => V; }`).
     */
    | Map( /* key */ MapKeyType, /* value */ Type)

    /**
     * Represents an `and` type
     * (e.g. TextDocumentParams & WorkDoneProgressParams`).
     */
    | And( /* items */ Array<Type>)

    /**
     * Represents an `or` type
     * (e.g. `Location | LocationLink`).
     */
    | Or( /* items */ Array<Type>)

    /**
     * Represents a `tuple` type
     * (e.g. `[integer, integer]`).
     */
    | Tuple( /* items */ Array<Type>)

    /**
     * Represents a literal structure
     * (e.g. `property: { start: uinteger; end: uinteger; }`).
     */
    | Literal( /* value */ StructureLiteral)

    /**
     * Represents a string literal type
     * (e.g. `kind: 'rename'`).
     */
    | StringLiteral( /* value */ String)

    /**
     * Represents an integer literal type
     * (e.g. `kind: 1`).
     */
    | IntegerLiteral( /* value */ Int64)

    /**
     * Represents a boolean literal type
     * (e.g. `kind: true`).
     */
    | BooleanLiteral( /* value */ Bool)

    /**
     * @throws DataModelException - if unable to deserialize DataModel
     */
    public static func deserialize(dm: DataModel): Type {
        let dms = match (dm) {
            case dms: DataModelStruct => dms
            case _ => throw DataModelException("expected `DataModelStruct`")
        }

        match (dms.getDeserializedOrThrow<String>("kind")) {
            case "base" => Base(dms.getDeserializedOrThrow("name"))
            case "reference" => Reference(dms.getDeserializedOrThrow("name"))
            case "array" => Array(dms.getDeserializedOrThrow("element"))
            case "map" => Map(dms.getDeserializedOrThrow("key"), dms.getDeserializedOrThrow("value"))
            case "and" => And(dms.getDeserializedOrThrow("items"))
            case "or" => Or(dms.getDeserializedOrThrow("items"))
            case "tuple" => Tuple(dms.getDeserializedOrThrow("items"))
            case "literal" => Literal(dms.getDeserializedOrThrow("value"))
            case "stringLiteral" => StringLiteral(dms.getDeserializedOrThrow("value"))
            case "integerLiteral" => IntegerLiteral(dms.getDeserializedOrThrow("value"))
            case "booleanLiteral" => BooleanLiteral(dms.getDeserializedOrThrow("value"))
            case kind => throw DataModelException("unknown \"kind\": \"${kind}\"")
        }
    }

    public func serialize(): DataModel {
        let dms = DataModelStruct()
        match (this) {
            case Base(baseTypes) => dms.add(field("kind", "base")).add(field("name", baseTypes))
            case Reference(ref) => dms.add(field("kind", "reference")).add(field("name", ref))
            case Array(element) => dms.add(field("kind", "array")).add(field("element", element))
            case Map(key, value) => dms.add(field("kind", "map")).add(field("key", key)).add(field("value", value))
            case And(items) => dms.add(field("kind", "and")).add(field("items", items))
            case Or(items) => dms.add(field("kind", "or")).add(field("items", items))
            case Tuple(items) => dms.add(field("kind", "tuple")).add(field("items", items))
            case Literal(value) => dms.add(field("kind", "literal")).add(field("value", value))
            case StringLiteral(value) => dms.add(field("kind", "stringLiteral")).add(field("value", value))
            case IntegerLiteral(value) => dms.add(field("kind", "integerLiteral")).add(field("value", value))
            case BooleanLiteral(value) => dms.add(field("kind", "booleanLiteral")).add(field("value", value))
        }
    }
}

/**
 * Defines an unnamed structure of an object literal.
 */
struct StructureLiteral <: Serializable<StructureLiteral> {
    StructureLiteral(
        /**
         * The properties.
         */
        let properties!: Array<Property>,

        /**
         * An optional documentation.
         */
        let documentation!: ?String = None,

        /**
         * Since when (release number) this property is
         * available. Is None if not known.
         */
        let since!: ?String = None,

        /**
         * All since tags in case there was more than one tag.
         * Is None if not known.
         */
        let sinceTags!: ?Array<String> = None,

        /**
         * Whether this is a proposed property. If omitted,
         * the structure is final.
         */
        let proposed!: Bool = false,

        /**
         * Whether the property is deprecated or not. If deprecated
         * the property contains the deprecation message.
         */
        let deprecated!: ?String = None
    ) {}

    /**
     * @throws DataModelException - if unable to deserialize DataModel
     */
    public static func deserialize(dm: DataModel): StructureLiteral {
        let dms = match (dm) {
            case dms: DataModelStruct => dms
            case _ => throw DataModelException("expected `DataModelStruct`")
        }

        StructureLiteral(
            properties: dms.getDeserializedOrThrow("properties"),
            documentation: dms.getDeserializedOrNone("documentation"),
            since: dms.getDeserializedOrNone("since"),
            sinceTags: dms.getDeserializedOrNone("sinceTags"),
            proposed: dms.getDeserializedOrNone<Bool>("proposed") ?? false,
            deprecated: dms.getDeserializedOrNone("deprecated"),
        )
    }

    public func serialize(): DataModel {
        let dms = DataModelStruct().add(field("properties", properties)).add(field("proposed", proposed))

        dms.addFieldIfSome("documentation", documentation)
        dms.addFieldIfSome("since", since)
        dms.addFieldIfSome("sinceTags", sinceTags)
        dms.addFieldIfSome("deprecated", deprecated)

        dms
    }
}

/**
 * Represents an object property.
 */
struct Property <: Serializable<Property> {
    Property(
        /**
         * The property name;
         */
        let name!: String,

        /**
         * The type of the property
         */
        let `type`!: Type,

        /**
         * Whether the property is optional. If
         * None, the property is mandatory.
         */
        let optional!: Bool = false,

        /**
         * An optional documentation.
         */
        let documentation!: ?String = None,

        /**
         * Since when (release number) this property is
         * available. Is None if not known.
         */
        let since!: ?String = None,

        /**
         * All since tags in case there was more than one tag.
         * Is None if not known.
         */
        let sinceTags!: ?Array<String> = None,

        /**
         * Whether this is a proposed property. If omitted,
         * the structure is final.
         */
        let proposed!: Bool = false,

        /**
         * Whether the property is deprecated or not. If deprecated
         * the property contains the deprecation message.
         */
        let deprecated!: ?String = None
    ) {}

    /**
     * @throws DataModelException - if unable to deserialize DataModel
     */
    public static func deserialize(dm: DataModel): Property {
        let dms = match (dm) {
            case dms: DataModelStruct => dms
            case _ => throw DataModelException("expected `DataModelStruct`")
        }

        Property(
            name: dms.getDeserializedOrThrow("name"),
            `type`: dms.getDeserializedOrThrow("type"),
            optional: dms.getDeserializedOrNone<Bool>("optional") ?? false,
            documentation: dms.getDeserializedOrNone("documentation"),
            since: dms.getDeserializedOrNone("since"),
            sinceTags: dms.getDeserializedOrNone("sinceTags"),
            proposed: dms.getDeserializedOrNone<Bool>("proposed") ?? false,
            deprecated: dms.getDeserializedOrNone("deprecated"),
        )
    }

    public func serialize(): DataModel {
        let dms = DataModelStruct()
            .add(field("name", name))
            .add(field("type", `type`))
            .add(field("optional", optional))
            .add(field("proposed", proposed))

        dms.addFieldIfSome("documentation", documentation)
        dms.addFieldIfSome("since", since)
        dms.addFieldIfSome("sinceTags", sinceTags)
        dms.addFieldIfSome("deprecated", deprecated)

        dms
    }
}

enum OneOrMany<T> {
    | One(T)
    | Many(Array<T>)
}

extend<T> OneOrMany<T> <: Serializable<OneOrMany<T>> where T <: Serializable<T> {
    public static func deserialize(dm: DataModel): OneOrMany<T> {
        match (dm) {
            case _: DataModelSeq => Many(Array<T>.deserialize(dm))
            case _ => One(T.deserialize(dm))
        }
    }

    public func serialize(): DataModel {
        match (this) {
            case One(v) => v.serialize()
            case Many(arr) => arr.serialize()
        }
    }
}

/**
 * Defines an enumeration entry.
 */
struct EnumerationEntry <: Serializable<EnumerationEntry> {
    EnumerationEntry(
        /**
         * The name of the enum item.
         */
        let name!: String,

        /**
         * The value.
         */
        let value!: IntegerOrString,

        /**
         * An optional documentation.
         */
        let documentation!: ?String = None,

        /**
         * Since when (release number) this property is
         * available. Is None if not known.
         */
        let since!: ?String = None,

        /**
         * All since tags in case there was more than one tag.
         * Is None if not known.
         */
        let sinceTags!: ?Array<String> = None,

        /**
         * Whether this is a proposed property. If omitted,
         * the structure is final.
         */
        let proposed!: Bool = false,

        /**
         * Whether the property is deprecated or not. If deprecated
         * the property contains the deprecation message.
         */
        let deprecated!: ?String = None
    ) {}

    /**
     * @throws DataModelException - if unable to deserialize DataModel
     */
    public static func deserialize(dm: DataModel): EnumerationEntry {
        let dms = match (dm) {
            case dms: DataModelStruct => dms
            case _ => throw DataModelException("expected `DataModelStruct`")
        }

        EnumerationEntry(
            name: dms.getDeserializedOrThrow("name"),
            value: dms.getDeserializedOrThrow("value"),
            documentation: dms.getDeserializedOrNone("documentation"),
            since: dms.getDeserializedOrNone("since"),
            sinceTags: dms.getDeserializedOrNone("sinceTags"),
            proposed: dms.getDeserializedOrNone<Bool>("proposed") ?? false,
            deprecated: dms.getDeserializedOrNone("deprecated"),
        )
    }

    public func serialize(): DataModel {
        let dms = DataModelStruct().add(field("name", name)).add(field("value", value)).add(field("proposed", proposed))

        dms.addFieldIfSome("documentation", documentation)
        dms.addFieldIfSome("since", since)
        dms.addFieldIfSome("sinceTags", sinceTags)
        dms.addFieldIfSome("deprecated", deprecated)

        dms
    }
}

enum EnumerationType <: Serializable<EnumerationType> {
    // string
    | String
    // integer
    | Integer
    // uinteger
    | UInteger

    /**
     * @throws DataModelException - if unable to deserialize DataModel
     */
    public static func deserialize(dm: DataModel): EnumerationType {
        let dms = match (dm) {
            case dms: DataModelStruct => dms
            case _ => throw DataModelException("expected `DataModelStruct`")
        }

        if ("base" != dms.getDeserializedOrThrow("kind")) {
            throw DataModelException("unexpected `kind` field value")
        }

        let nameDataModel = match (dms.getOrThrow("name")) {
            case dmStr: DataModelString => dmStr
            case _ => throw DataModelException("expected `DataModelString`")
        }

        match (nameDataModel.getValue()) {
            case "string" => String
            case "integer" => Integer
            case "uinteger" => UInteger
            case _ => throw DataModelException("invalid `EnumerationType` value")
        }
    }

    public func serialize(): DataModel {
        DataModelStruct().add(field("kind", "base")).add(field("name", match (this) {
            case String => "string"
            case Integer => "integer"
            case UInteger => "uinteger"
        }))
    }
}
