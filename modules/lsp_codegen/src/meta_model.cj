package lsp_codegen

import stdx.serialization.serialization.*
import stdxx.*
import stdxx.deriving.*

/**
 * The actual meta model.
 * @note specification taken from: https://microsoft.github.io/language-server-protocol/specifications/lsp/3.18/metaModel/metaModel.ts
 */
@DeriveExt[Serializable]
struct MetaModel {
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
}

@DeriveExt[Serializable]
struct MetaData {
    MetaData(
        /**
         * The protocol version.
         */
        let version!: String) {}
}

/**
 * Represents a LSP request
 */
@DeriveExt[Serializable]
@DeriveExtSerializable[skipNone]
struct Request {
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
}

/**
 * Represents a LSP notification
 */
@DeriveExt[Serializable]
@DeriveExtSerializable[skipNone]
struct Notification {
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
}

/**
 * Defines the structure of an object literal.
 */
@DeriveExt[Serializable]
@DeriveExtSerializable[skipNone]
struct Structure {
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
}

/**
 * Defines an enumeration.
 */
@DeriveExt[Serializable]
@DeriveExtSerializable[skipNone]
struct Enumeration {
    Enumeration(
        /**
         * The name of the enumeration.
         */
        let name!: String,

        /**
         * The type of the elements.
         */
        @DeriveExtSerializable[rename: "type"] let enumerationType!: EnumerationType,

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
}

/**
 * Defines a type alias.
 * (e.g. `type Definition = Location | LocationLink`)
 */
@DeriveExt[Serializable]
@DeriveExtSerializable[skipNone]
struct TypeAlias {
    TypeAlias(
        /**
         * The name of the type alias.
         */
        let name!: String,

        /**
         * The aliased type.
         */
        @DeriveExtSerializable[rename: "type"] let typeAliasType!: Type,

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
}

@DeriveExt[Serializable]
enum BaseTypes {
    // URI
    | @DeriveExtSerializable[value: "URI"]
    Uri
    | DocumentUri
    // integer
    | @DeriveExtSerializable[value: "integer"]
    Integer
    // uinteger
    | @DeriveExtSerializable[value: "uinteger"]
    UInteger
    // decimal
    | @DeriveExtSerializable[value: "decimal"]
    Decimal
    | RegExp
    // string
    | @DeriveExtSerializable[value: "string"]
    String
    // boolean
    | @DeriveExtSerializable[value: "boolean"]
    Boolean
    // null
    | @DeriveExtSerializable[value: "null"]
    Null
}

/**
 * Indicates in which direction a message is sent in the protocol.
 */
@DeriveExt[Serializable]
enum MessageDirection {
    // clientToServer
    | @DeriveExtSerializable[value: "clientToServer"]
    ClientToServer
    // serverToClient
    | @DeriveExtSerializable[value: "serverToClient"]
    ServerToClient
    // both
    | @DeriveExtSerializable[value: "both"]
    Both
}

@DeriveExt[Serializable]
enum MapKeyName {
    // URI
    | @DeriveExtSerializable[value: "URI"]
    Uri
    | DocumentUri
    // string
    | @DeriveExtSerializable[value: "string"]
    String
    // integer
    | @DeriveExtSerializable[value: "integer"]
    Integer
}

/**
 * Represents a type that can be used as a key in a
 * map type. If a reference type is used then the
 * type must either resolve to a `string` or `integer`
 * type. (e.g. `type ChangeAnnotationIdentifier === string`).
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
    /**
     * Represents a base type like `string` or `DocumentUri`.
     */
    | @DeriveExtSerializable[value: "base", payload: ["name"]]
    Base( /* name */ BaseTypes)

    /**
     * Represents a reference to another type (e.g. `TextDocument`).
     * This is either a `Structure`, a `Enumeration` or a `TypeAlias`
     * in the same meta model.
     */
    | @DeriveExtSerializable[value: "reference", payload: ["name"]]
    Reference( /* name */ String)

    /**
     * Represents an array type (e.g. `TextDocument[]`).
     */
    | @DeriveExtSerializable[value: "array", payload: ["element"]]
    Array( /* element */ Type)

    /**
     * Represents a JSON object map
     * (e.g. `interface Map<K extends string | integer, V> { [key: K] => V; }`).
     */
    | @DeriveExtSerializable[value: "map", payload: ["key", "value"]]
    Map( /* key */ MapKeyType, /* value */ Type)

    /**
     * Represents an `and` type
     * (e.g. TextDocumentParams & WorkDoneProgressParams`).
     */
    | @DeriveExtSerializable[value: "and", payload: ["items"]]
    And( /* items */ Array<Type>)

    /**
     * Represents an `or` type
     * (e.g. `Location | LocationLink`).
     */
    | @DeriveExtSerializable[value: "or", payload: ["items"]]
    Or( /* items */ Array<Type>)

    /**
     * Represents a `tuple` type
     * (e.g. `[integer, integer]`).
     */
    | @DeriveExtSerializable[value: "tuple", payload: ["items"]]
    Tuple( /* items */ Array<Type>)

    /**
     * Represents a literal structure
     * (e.g. `property: { start: uinteger; end: uinteger; }`).
     */
    | @DeriveExtSerializable[value: "literal", payload: ["value"]]
    Literal( /* value */ StructureLiteral)

    /**
     * Represents a string literal type
     * (e.g. `kind: 'rename'`).
     */
    | @DeriveExtSerializable[value: "stringLiteral", payload: ["value"]]
    StringLiteral( /* value */ String)

    /**
     * Represents an integer literal type
     * (e.g. `kind: 1`).
     */
    | @DeriveExtSerializable[value: "integerLiteral", payload: ["value"]]
    IntegerLiteral( /* value */ Int64)

    /**
     * Represents a boolean literal type
     * (e.g. `kind: true`).
     */
    | @DeriveExtSerializable[value: "booleanLiteral", payload: ["value"]]
    BooleanLiteral( /* value */ Bool)
}

/**
 * Defines an unnamed structure of an object literal.
 */
@DeriveExt[Serializable]
@DeriveExtSerializable[skipNone]
struct StructureLiteral {
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
}

/**
 * Represents an object property.
 */
@DeriveExt[Serializable]
@DeriveExtSerializable[skipNone]
struct Property {
    Property(
        /**
         * The property name;
         */
        let name!: String,

        /**
         * The type of the property
         */
        @DeriveExtSerializable[rename: "type"] let propertyType!: Type,

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
}

@DeriveExt[Serializable]
enum OneOrMany<T> {
    | One(T)
    | Many(Array<T>)
}

/**
 * Defines an enumeration entry.
 */
@DeriveExt[Serializable]
@DeriveExtSerializable[skipNone]
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
