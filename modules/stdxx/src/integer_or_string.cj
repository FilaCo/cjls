package stdxx

import std.deriving.*
import stdx.serialization.serialization.*

@Derive[Equatable, Hashable]
public enum IntegerOrString <: Serializable<IntegerOrString> & ToString {
    | Integer(Int32)
    | String(String)

    /**
     * @throws DataModelException - if not a DataModelInt or DataModelString
     */
    public static func deserialize(dm: DataModel): IntegerOrString {
        match (dm) {
            case i: DataModelInt =>
                let value = try {
                    Int32(i.getValue())
                } catch (e: OverflowException) {
                    throw DataModelException("invalid integer\nCause: ${e}")
                }
                Integer(value)
            case s: DataModelString => String(s.getValue())
            case _ => throw DataModelException("expected integer or string")
        }
    }

    public func serialize(): DataModel {
        match (this) {
            case Integer(i) => DataModelInt(Int64(i))
            case String(s) => DataModelString(s)
        }
    }

    public func toString(): String {
        match (this) {
            case Integer(i) => i.toString()
            case String(s) => s
        }
    }

    public func isInteger(): Bool {
        match (this) {
            case Integer(_) => true
            case String(_) => false
        }
    }

    public func isString(): Bool {
        !isInteger()
    }

    /**
     * @throws UnexpectedVariantException - if it holds a `String`
     */
    public func getIntegerOrThrow(): Int32 {
        match (this) {
            case Integer(int) => int
            case String(_) => throw UnexpectedVariantException("Integer", "String")
        }
    }

    /**
     * @throws UnexpectedVariantException - if it holds an `Integer`
     */
    public func getStringOrThrow(): String {
        match (this) {
            case String(str) => str
            case Integer(_) => throw UnexpectedVariantException("String", "Integer")
        }
    }
}

// in an extension of its own: inside the enum body these would hide the derived `==` they call
extend IntegerOrString <: Equatable<Int32> & Equatable<String> {
    public operator func ==(other: Int32): Bool {
        this == Integer(other)
    }

    public operator func ==(other: String): Bool {
        this == String(other)
    }
}
