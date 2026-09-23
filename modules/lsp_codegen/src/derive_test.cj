package lsp_codegen

import std.io.{ByteBuffer, readToEnd}
import std.unittest.*
import std.unittest.testmacro.*
import stdxx.*

private func emittedDerives(derives: Array<DeriveIr>): String {
    let output = ByteBuffer()
    let sut = CjEmitter(output)
    sut.emitDerives(derives)
    sut.flush()

    unsafe { String.fromUtf8(readToEnd(output)) }
}

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
        let actual = emittedDerives([DeriveIr.Serializable(options)])

        // assert
        @PowerAssert(expected, actual)
    }

    @TestCase
    func noOptionsLeaveNoMarker() {
        // arrange
        let expected = """
@DeriveExt[Serializable]
@Derive[Equatable, Hashable]
"""

        // act
        let actual = emittedDerives(
            [DeriveIr.Serializable(SerializableTypeOptions()), DeriveIr.Equatable, DeriveIr.Hashable])

        // assert
        @PowerAssert(expected, actual)
    }

    @TestCase
    func nothingToDeriveEmitsNothing() {
        // act & assert
        @Expect("", emittedDerives([]))
    }

    @TestCase
    func aMemberMarkerListsItsValueAndOther() {
        // act
        let actual = serializableMarkerOf(SerializableMemberOptions(value: IntegerOrString.Integer(1), other: true))

        // assert
        @Expect("@DeriveExtSerializable[value: 1, other]", actual.toString())
    }
}
