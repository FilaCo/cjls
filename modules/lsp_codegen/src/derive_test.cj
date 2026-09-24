package lsp_codegen

import std.unittest.*
import std.unittest.testmacro.*
import stdxx.*

@Test
class EmitDerivesTest {
    @TestCase
    func aTaggedStructNamesItsTagAndValue() {
        // arrange
        let options = SerializableTypeOptions(tag: SerializableTag(field: "kind", value: "create"))
        let expected = """
@DeriveExt[Serializable]
@DeriveExtSerializable[tag: "kind", value: "create"]
"""

        // act
        let actual = emittedBy {emitter => emitter.emitDerives([DeriveIr.Serializable(options)])}

        // assert
        @PowerAssert(expected, actual)
    }

    @TestCase
    func noOptionsLeaveNoMarker() {
        // arrange
        let derives = [DeriveIr.Serializable(SerializableTypeOptions()), DeriveIr.Equatable, DeriveIr.Hashable]
        let expected = """
@DeriveExt[Serializable]
@Derive[Equatable, Hashable]
"""

        // act
        let actual = emittedBy {emitter => emitter.emitDerives(derives)}

        // assert
        @PowerAssert(expected, actual)
    }

    @TestCase
    func aMemberMarkerListsItsValueAndOther() {
        // act
        let actual = serializableMarkerOf(SerializableMemberOptions(value: IntegerOrString.Integer(1), other: true))

        // assert
        @Expect("@DeriveExtSerializable[value: 1, other]", actual.toString())
    }
}
