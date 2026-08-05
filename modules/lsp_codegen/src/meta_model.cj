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
        if (let dms: DataModelStruct <- dm) {
            return MetaModel(
                metaData: MetaData.deserialize(dms.getOrThrow("metaData")),
                requests: Array<Request>.deserialize(dms.getOrThrow("requests")),
                notifications: Array<Notification>.deserialize(dms.getOrThrow("notifications")),
                structures: Array<Structure>.deserialize(dms.getOrThrow("structures")),
                enumerations: Array<Enumeration>.deserialize(dms.getOrThrow("enumerations")),
                typeAliases: Array<TypeAlias>.deserialize(dms.getOrThrow("typeAliases"))
            )
        }

        throw DataModelException("expected `DataModelStruct`")
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
        if (let dms: DataModelStruct <- dm) {
            return MetaData(version: String.deserialize(dms.getOrThrow("version")))
        }

        throw DataModelException("expected `DataModelStruct`")
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
        let documentationData!: DocumentationData = DocumentationData(),

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
        throw UnsupportedException()
    }

    public func serialize(): DataModel {
        throw UnsupportedException()
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
        let documentationData!: DocumentationData = DocumentationData(),

        /**
         * The client capability property path if any.
         */
        let clientCapability!: ?String = None,

        /**
         * The server capability property path if any.
         */
        let serverCapability!: ?String = None
    ) {}

    public static func deserialize(dm: DataModel): Notification {
        throw UnsupportedException()
    }

    public func serialize(): DataModel {
        throw UnsupportedException()
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
        let documentationData!: DocumentationData = DocumentationData()
    ) {}

    public static func deserialize(dm: DataModel): Structure {
        throw UnsupportedException()
    }

    public func serialize(): DataModel {
        throw UnsupportedException()
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
        let documentationData!: DocumentationData = DocumentationData()
    ) {}

    public static func deserialize(dm: DataModel): Enumeration {
        throw UnsupportedException()
    }

    public func serialize(): DataModel {
        throw UnsupportedException()
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
        let documentationData!: DocumentationData = DocumentationData()
    ) {}

    public static func deserialize(dm: DataModel): TypeAlias {
        throw UnsupportedException()
    }

    public func serialize(): DataModel {
        throw UnsupportedException()
    }
}

enum BaseTypes {
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

    public static func deserialize(dm: DataModel): MessageDirection {
        if (let dms: DataModelString <- dm) {
            return match (dms.getValue()) {
                case "clientToServer" => ClientToServer
                case "serverToClient" => ServerToClient
                case "both" => Both
                case _ => throw DataModelException("invalid MessageDirection value")
            }
        }

        throw DataModelException("expected `DataModelString`")
    }

    public func serialize(): DataModel {
        match (this) {
            case ClientToServer => DataModelString("clientToServer")
            case ServerToClient => DataModelString("serverToClient")
            case Both => DataModelString("both")
        }
    }
}

enum MapKeyName {
    | Uri | DocumentUri | String | Integer
}

enum MapKeyType {
    | BaseType(MapKeyName)
    | ReferenceType(String)
}

enum Type {
    /**
     * Represents a base type like `string` or `DocumentUri`.
     */
    | BaseType(BaseTypes)

    /**
     * Represents a reference to another type (e.g. `TextDocument`).
     * This is either a `Structure`, a `Enumeration` or a `TypeAlias`
     * in the same meta model.
     */
    | ReferenceType(String)

    /**
     * Represents an array type (e.g. `TextDocument[]`).
     */
    | ArrayType(Type)

    /**
     * Represents a JSON object map
     * (e.g. `interface Map<K extends string | integer, V> { [key: K] => V; }`).
     */
    | MapType( /* key */ MapKeyType, /* value */ Type)

    /**
     * Represents an `and` type
     * (e.g. TextDocumentParams & WorkDoneProgressParams`).
     */
    | AndType(Array<Type>)

    /**
     * Represents an `or` type
     * (e.g. `Location | LocationLink`).
     */
    | OrType(Array<Type>)

    /**
     * Represents a `tuple` type
     * (e.g. `[integer, integer]`).
     */
    | TupleType(Array<Type>)

    /**
     * Represents a literal structure
     * (e.g. `property: { start: uinteger; end: uinteger; }`).
     */
    | LiteralType(StructureLiteral)

    /**
     * Represents a string literal type
     * (e.g. `kind: 'rename'`).
     */
    | StringLiteralType(String)

    /**
     * Represents an integer literal type
     * (e.g. `kind: 1`).
     */
    | IntegerLiteralType(Int64)

    /**
     * Represents a boolean literal type
     * (e.g. `kind: true`).
     */
    | BooleanLiteralType(Bool)
}

/**
 * Defines an unnamed structure of an object literal.
 */
struct StructureLiteral {
    StructureLiteral(
        /**
         * The properties.
         */
        let properties!: Array<Property>,
        let documentationData!: DocumentationData = DocumentationData()
    ) {}
}

/**
 * Represents an object property.
 */
struct Property {
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
        let documentationData!: DocumentationData = DocumentationData()
    ) {}
}

struct DocumentationData {
    DocumentationData(
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
}

enum OneOrMany<T> {
    | One(T)
    | Many(Array<T>)
}

/**
 * Defines an enumeration entry.
 */
struct EnumerationEntry {
    EnumerationEntry(
        /**
         * The name of the enum item.
         */
        let name!: String,

        /**
         * The value.
         */
        let value!: IntegerOrString,
        let documentationData!: DocumentationData = DocumentationData()
    ) {}
}

enum EnumerationType {
    | String
    | Integer
    | UInteger
}
