package stdxx

// no `std.collection` here on purpose: what the derive expands to has to compile with only the
// imports it needs anyway, and the tuple variants below once wrote themselves through `ArrayList`
import stdx.serialization.serialization.*
import stdxx.deriving.*

/**
 * The shape of `ParameterInformation.label`: `string | [uinteger, uinteger]`.
 */
@DeriveExt[Serializable]
enum DerivedLabel {
    | Text(String)
    | Offsets(UInt32, UInt32)
    | Signed(Int64, Int64)
}
