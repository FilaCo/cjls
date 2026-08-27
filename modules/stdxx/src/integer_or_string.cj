package stdxx

import stdx.serialization.serialization.*

/**
 * `integer | string` type.
 */
public enum IntegerOrString <: Serializable<IntegerOrString> & ToString & Equatable<IntegerOrString> & Equatable<Int32> &
    Equatable<String> & Hashable {
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

    public operator func ==(other: IntegerOrString): Bool {
        match ((this, other)) {
            case (Integer(lhs), Integer(rhs)) => lhs == rhs
            case (String(lhs), String(rhs)) => lhs == rhs
            case _ => false
        }
    }

    public operator func ==(other: Int32): Bool {
        this == Integer(other)
    }

    public operator func ==(other: String): Bool {
        this == String(other)
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

    public func hashCode(): Int64 {
        match (this) {
            case Integer(int) => int.hashCode()
            case String(str) => str.hashCode()
        }
    }
}
