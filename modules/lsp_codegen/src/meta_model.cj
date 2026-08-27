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
        let dms = dm.asStructOrThrow()

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
        let dms = dm.asStructOrThrow()

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
        let proposed!: ?Bool = None,

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
        let dms = dm.asStructOrThrow()

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
            proposed: dms.getDeserializedOrNone("proposed"),
            deprecated: dms.getDeserializedOrNone("deprecated"),
            clientCapability: dms.getDeserializedOrNone("clientCapability"),
            serverCapability: dms.getDeserializedOrNone("serverCapability"),
        )
    }

    public func serialize(): DataModel {
        DataModelStruct()
            .add(field("method", method))
            .addFieldIfSome("typeName", typeName)
            .addFieldIfSome("params", params)
            .add(field("result", result))
            .addFieldIfSome("partialResult", partialResult)
            .addFieldIfSome("errorData", errorData)
            .addFieldIfSome("registrationMethod", registrationMethod)
            .addFieldIfSome("registrationOptions", registrationOptions)
            .add(field("messageDirection", messageDirection))
            .addFieldIfSome("documentation", documentation)
            .addFieldIfSome("since", since)
            .addFieldIfSome("sinceTags", sinceTags)
            .addFieldIfSome("proposed", proposed)
            .addFieldIfSome("deprecated", deprecated)
            .addFieldIfSome("clientCapability", clientCapability)
            .addFieldIfSome("serverCapability", serverCapability)
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
        let proposed!: ?Bool = None,

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
        let dms = dm.asStructOrThrow()

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
            proposed: dms.getDeserializedOrNone("proposed"),
            deprecated: dms.getDeserializedOrNone("deprecated"),
            clientCapability: dms.getDeserializedOrNone("clientCapability"),
            serverCapability: dms.getDeserializedOrNone("serverCapability"),
        )
    }

    public func serialize(): DataModel {
        DataModelStruct()
            .add(field("method", method))
            .addFieldIfSome("typeName", typeName)
            .addFieldIfSome("params", params)
            .addFieldIfSome("registrationMethod", registrationMethod)
            .addFieldIfSome("registrationOptions", registrationOptions)
            .add(field("messageDirection", messageDirection))
            .addFieldIfSome("documentation", documentation)
            .addFieldIfSome("since", since)
            .addFieldIfSome("sinceTags", sinceTags)
            .addFieldIfSome("proposed", proposed)
            .addFieldIfSome("deprecated", deprecated)
            .addFieldIfSome("clientCapability", clientCapability)
            .addFieldIfSome("serverCapability", serverCapability)
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
        let proposed!: ?Bool = None,

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
        let dms = dm.asStructOrThrow()

        Structure(
            name: dms.getDeserializedOrThrow("name"),
            extends: dms.getDeserializedOrNone("extends"),
            mixins: dms.getDeserializedOrNone("mixins"),
            properties: dms.getDeserializedOrThrow("properties"),
            documentation: dms.getDeserializedOrNone("documentation"),
            since: dms.getDeserializedOrNone("since"),
            sinceTags: dms.getDeserializedOrNone("sinceTags"),
            proposed: dms.getDeserializedOrNone("proposed"),
            deprecated: dms.getDeserializedOrNone("deprecated"),
        )
    }

    public func serialize(): DataModel {
        DataModelStruct()
            .add(field("name", name))
            .addFieldIfSome("extends", extends)
            .addFieldIfSome("mixins", mixins)
            .add(field("properties", properties))
            .addFieldIfSome("documentation", documentation)
            .addFieldIfSome("since", since)
            .addFieldIfSome("sinceTags", sinceTags)
            .addFieldIfSome("proposed", proposed)
            .addFieldIfSome("deprecated", deprecated)
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
        let supportsCustomValues!: ?Bool = None,

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
        let proposed!: ?Bool = None,

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
        let dms = dm.asStructOrThrow()

        Enumeration(
            name: dms.getDeserializedOrThrow("name"),
            `type`: dms.getDeserializedOrThrow("type"),
            values: dms.getDeserializedOrThrow("values"),
            supportsCustomValues: dms.getDeserializedOrNone("supportsCustomValues"),
            documentation: dms.getDeserializedOrNone("documentation"),
            since: dms.getDeserializedOrNone("since"),
            sinceTags: dms.getDeserializedOrNone("sinceTags"),
            proposed: dms.getDeserializedOrNone("proposed"),
            deprecated: dms.getDeserializedOrNone("deprecated"),
        )
    }

    public func serialize(): DataModel {
        DataModelStruct()
            .add(field("name", name))
            .add(field("type", `type`))
            .add(field("values", values))
            .addFieldIfSome("supportsCustomValues", supportsCustomValues)
            .addFieldIfSome("documentation", documentation)
            .addFieldIfSome("since", since)
            .addFieldIfSome("sinceTags", sinceTags)
            .addFieldIfSome("proposed", proposed)
            .addFieldIfSome("deprecated", deprecated)
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
        let proposed!: ?Bool = None,

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
        let dms = dm.asStructOrThrow()

        TypeAlias(
            name: dms.getDeserializedOrThrow("name"),
            `type`: dms.getDeserializedOrThrow("type"),
            documentation: dms.getDeserializedOrNone("documentation"),
            since: dms.getDeserializedOrNone("since"),
            sinceTags: dms.getDeserializedOrNone("sinceTags"),
            proposed: dms.getDeserializedOrNone("proposed"),
            deprecated: dms.getDeserializedOrNone("deprecated"),
        )
    }

    public func serialize(): DataModel {
        DataModelStruct()
            .add(field("name", name))
            .add(field("type", `type`))
            .addFieldIfSome("documentation", documentation)
            .addFieldIfSome("since", since)
            .addFieldIfSome("sinceTags", sinceTags)
            .addFieldIfSome("proposed", proposed)
            .addFieldIfSome("deprecated", deprecated)
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
        match (dm.asStringOrThrow()) {
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
        match (dm.asStringOrThrow()) {
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
    // string
    | String
    // integer
    | Integer

    /**
     * @throws DataModelException - if unable to deserialize DataModel
     */
    public static func deserialize(dm: DataModel): MapKeyName {
        match (dm.asStringOrThrow()) {
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
        let dms = dm.asStructOrThrow()

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
        let dms = dm.asStructOrThrow()

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
        let proposed!: ?Bool = None,

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
        let dms = dm.asStructOrThrow()

        StructureLiteral(
            properties: dms.getDeserializedOrThrow("properties"),
            documentation: dms.getDeserializedOrNone("documentation"),
            since: dms.getDeserializedOrNone("since"),
            sinceTags: dms.getDeserializedOrNone("sinceTags"),
            proposed: dms.getDeserializedOrNone("proposed"),
            deprecated: dms.getDeserializedOrNone("deprecated"),
        )
    }

    public func serialize(): DataModel {
        DataModelStruct()
            .add(field("properties", properties))
            .addFieldIfSome("documentation", documentation)
            .addFieldIfSome("since", since)
            .addFieldIfSome("sinceTags", sinceTags)
            .addFieldIfSome("proposed", proposed)
            .addFieldIfSome("deprecated", deprecated)
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
        let optional!: ?Bool = None,

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
        let proposed!: ?Bool = None,

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
        let dms = dm.asStructOrThrow()

        Property(
            name: dms.getDeserializedOrThrow("name"),
            `type`: dms.getDeserializedOrThrow("type"),
            optional: dms.getDeserializedOrNone("optional"),
            documentation: dms.getDeserializedOrNone("documentation"),
            since: dms.getDeserializedOrNone("since"),
            sinceTags: dms.getDeserializedOrNone("sinceTags"),
            proposed: dms.getDeserializedOrNone("proposed"),
            deprecated: dms.getDeserializedOrNone("deprecated"),
        )
    }

    public func serialize(): DataModel {
        DataModelStruct()
            .add(field("name", name))
            .add(field("type", `type`))
            .addFieldIfSome("optional", optional)
            .addFieldIfSome("documentation", documentation)
            .addFieldIfSome("since", since)
            .addFieldIfSome("sinceTags", sinceTags)
            .addFieldIfSome("proposed", proposed)
            .addFieldIfSome("deprecated", deprecated)
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
        let proposed!: ?Bool = None,

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
        let dms = dm.asStructOrThrow()

        EnumerationEntry(
            name: dms.getDeserializedOrThrow("name"),
            value: dms.getDeserializedOrThrow("value"),
            documentation: dms.getDeserializedOrNone("documentation"),
            since: dms.getDeserializedOrNone("since"),
            sinceTags: dms.getDeserializedOrNone("sinceTags"),
            proposed: dms.getDeserializedOrNone("proposed"),
            deprecated: dms.getDeserializedOrNone("deprecated"),
        )
    }

    public func serialize(): DataModel {
        DataModelStruct()
            .add(field("name", name))
            .add(field("value", value))
            .addFieldIfSome("documentation", documentation)
            .addFieldIfSome("since", since)
            .addFieldIfSome("sinceTags", sinceTags)
            .addFieldIfSome("proposed", proposed)
            .addFieldIfSome("deprecated", deprecated)
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
        let dms = dm.asStructOrThrow()

        // NB: `String` here resolves to this enum's own constructor, not the type — so the name cannot be read with
        // `getDeserializedOrThrow<String>` the way the other deserializers do it.
        if ("base" != dms.getDeserializedOrThrow("kind")) {
            throw DataModelException("unexpected `kind` field value")
        }

        match (dms.getOrThrow("name").asStringOrThrow()) {
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
