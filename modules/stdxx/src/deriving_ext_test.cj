package stdxx

import std.deriving.*
import std.unittest.*
import std.unittest.testmacro.*
import std.collection.*
import stdx.serialization.serialization.*
import stdxx.serialization.*
import stdxx.deriving.*

@DeriveExt[Serializable]
struct DerivedPosition {
    DerivedPosition(let line!: Int64, let character!: Int64) {}
}

@DeriveExt[Serializable]
struct DerivedShapes {
    DerivedShapes(
        let required!: String,
        let nullable!: Nullable<String>,
        let optional!: ?String = None,
        let optionalNullable!: ?Nullable<String> = None
    ) {}
}

@DeriveExt[Serializable]
@DeriveExtSerializable[skipNone]
struct DerivedSkipped {
    DerivedSkipped(
        let required!: String,
        let optional!: ?String = None,
        let optionalNullable!: ?Nullable<String> = None
    ) {}
}

@DeriveExt[Serializable]
struct DerivedRenamedAndSkipped {
    DerivedRenamedAndSkipped(@DeriveExtSerializable[rename: "textDocument", skipNone] let document!: ?String = None) {}
}

@DeriveExt[Serializable]
struct DerivedPartlySkipped {
    DerivedPartlySkipped(
        @DeriveExtSerializable[skipNone] let skipped!: ?String = None,
        let kept!: ?String = None
    ) {}
}

@DeriveExt[Serializable]
@DeriveExtSerializable[skipNone]
public struct DerivedPublicSkipped {
    public DerivedPublicSkipped(
        public let required!: String,
        public let optional!: ?String = None
    ) {}
}

@DeriveExt[Serializable]
struct DerivedNames {
    DerivedNames(
        @DeriveExtSerializable[rename: "textDocument"] let document!: String,
        let `type`!: String
    ) {}
}

@DeriveExt[Serializable]
struct DerivedBox<T> {
    DerivedBox(let value!: T) {}
}

@DeriveExt[Serializable]
struct DerivedPositional {
    DerivedPositional(let x: Int64, let y: Int64) {}
}

@DeriveExt[Serializable]
@Derive[ToString]
struct DerivedAndDescribed {
    DerivedAndDescribed(let name!: String) {}
}

/**
 * An open enumeration: a newtype with constants, the marker between the two derives.
 */
@DeriveExt[Serializable]
@DeriveExtSerializable[transparent]
@Derive[Equatable, Hashable]
public struct DerivedOpenCode {
    public const DerivedOpenCode(public let value: Int32) {}

    public static const PARSE_ERROR: DerivedOpenCode = DerivedOpenCode(-32700)
}

@DeriveExt[Serializable]
@DeriveExtSerializable[tag: "kind", value: "create", skipNone]
struct DerivedCreateFile {
    DerivedCreateFile(let uri!: String, let overwrite!: ?Bool = None) {}
}

@DeriveExt[Serializable]
@DeriveExtSerializable[tag: "kind", value: "delete", skipNone]
struct DerivedDeleteFile {
    DerivedDeleteFile(let uri!: String, let recursive!: ?Bool = None) {}
}

@DeriveExt[Serializable]
enum DerivedFileOperation {
    | Create(DerivedCreateFile)
    | Delete(DerivedDeleteFile)
}

@DeriveExt[Serializable]
@DeriveExtSerializable[transparent]
struct DerivedOpenUnsigned {
    DerivedOpenUnsigned(let value: UInt32) {}
}

@DeriveExt[Serializable]
@DeriveExtSerializable[transparent]
struct DerivedOpenKind {
    DerivedOpenKind(let `value`!: String) {}
}

@Test
class DeriveSerializableTest {
    @TestCase
    func requiredFieldsRoundTrip() {
        // arrange
        let position = DerivedPosition(line: 3, character: 14)

        // act
        let dms = position.serialize().asStructOrThrow()
        let restored = DerivedPosition.deserialize(dms)

        // assert
        @Expect(3, dms.getOrThrow("line").asIntOrThrow())
        @Expect(14, dms.getOrThrow("character").asIntOrThrow())
        @Expect(3, restored.line)
        @Expect(14, restored.character)
    }

    @TestCase
    func aMissingRequiredFieldThrows() {
        // arrange
        let dms = DataModelStruct().add(field("line", 3))

        // act
        let e = @AssertThrows[DataModelException](DerivedPosition.deserialize(dms))

        // assert
        @Expect("required field \"character\" is absent", e.message)
    }

    @TestCase
    func positionalFieldsRoundTrip() {
        // act
        let restored = DerivedPositional.deserialize(DerivedPositional(1, 2).serialize())

        // assert
        @Expect(1, restored.x)
        @Expect(2, restored.y)
    }

    @TestCase
    func aGenericFieldRoundTripsThroughItsOwnSerializable() {
        // act
        let restored = DerivedBox<String>.deserialize(DerivedBox(value: "boxed").serialize())

        // assert
        @Expect("boxed", restored.value)
    }

    @TestCase
    func derivingLeavesRoomForDerive() {
        // arrange
        let described = DerivedAndDescribed(name: "x")

        // act & assert
        @Expect("x", described.serialize().asStructOrThrow().getOrThrow("name").asStringOrThrow())
        @Expect("DerivedAndDescribed(name: x)", described.toString())
    }

    @TestCase
    func renameAndBackquotesDecideTheWireName() {
        // arrange
        let names = DerivedNames(document: "file:///a.cj", `type`: "cangjie")

        // act
        let dms = names.serialize().asStructOrThrow()
        let restored = DerivedNames.deserialize(dms)

        // assert
        @Expect("file:///a.cj", dms.getOrThrow("textDocument").asStringOrThrow())
        @Expect("cangjie", dms.getOrThrow("type").asStringOrThrow())
        @Expect(dms.getOrNone("document").isNone())
        @Expect("file:///a.cj", restored.document)
        @Expect("cangjie", restored.`type`)
    }
}

@Test
class DeriveSerializableNullabilityTest {
    @TestCase
    func withoutSkipNoneEveryFieldIsWritten() {
        // arrange
        let shapes = DerivedShapes(required: "r", nullable: Null, optional: "o")

        // act
        let dms = shapes.serialize().asStructOrThrow()

        // assert
        @Expect("o", dms.getOrThrow("optional").asStringOrThrow())
        @Expect(dms.getOrThrow("nullable") is DataModelNull)
        @Expect(dms.getOrThrow("optionalNullable") is DataModelNull)
    }

    @TestCase
    func anExplicitNullReadsAsNoneRatherThanThrowing() {
        // arrange
        let dms = DataModelStruct()
            .add(field("required", "r"))
            .add(Field("nullable", DataModelNull()))
            .add(Field("optional", DataModelNull()))

        // act
        let restored = DerivedShapes.deserialize(dms)

        // assert
        @Expect(restored.optional.isNone())
        @Expect(restored.nullable.isNull())
    }

    @TestCase
    func anOptionalNullableTellsAbsentFromNull() {
        // arrange
        let absent = DataModelStruct().add(field("required", "r")).add(Field("nullable", DataModelNull()))
        let present = DataModelStruct()
            .add(field("required", "r"))
            .add(Field("nullable", DataModelNull()))
            .add(Field("optionalNullable", DataModelNull()))

        // act
        let restoredAbsent = DerivedShapes.deserialize(absent)
        let restoredNull = DerivedShapes.deserialize(present)

        // assert
        @Expect(restoredAbsent.optionalNullable.isNone())
        @Expect(restoredNull.optionalNullable.getOrThrow().isNull())
    }
}

@Test
class DeriveSkipNoneTest {
    @TestCase
    func onTheTypeItOmitsEveryNoneFieldAndReadsThemBack() {
        // act
        let dms = DerivedSkipped(required: "r").serialize().asStructOrThrow()
        let restored = DerivedSkipped.deserialize(dms)

        // assert
        @Expect(dms.getOrNone("optional").isNone())
        @Expect(dms.getOrNone("optionalNullable").isNone())
        @Expect("r", restored.required)
        @Expect(restored.optional.isNone())
        @Expect(restored.optionalNullable.isNone())
    }

    @TestCase
    func onTheTypeItStillWritesAnExplicitNull() {
        // act
        let dms = DerivedSkipped(required: "r", optionalNullable: Null).serialize().asStructOrThrow()

        // assert
        @Expect(dms.getOrThrow("optionalNullable") is DataModelNull)
    }

    @TestCase
    func onASingleFieldItLeavesTheRestAlone() {
        // act
        let dms = DerivedPartlySkipped().serialize().asStructOrThrow()

        // assert
        @Expect(dms.getOrNone("skipped").isNone())
        @Expect(dms.getOrThrow("kept") is DataModelNull)
    }

    @TestCase
    func modifiersDoNotHideTheMarkerOrTheFields() {
        // act
        let dms = DerivedPublicSkipped(required: "r").serialize().asStructOrThrow()
        let restored = DerivedPublicSkipped.deserialize(dms)

        // assert
        @Expect(dms.getOrNone("optional").isNone())
        @Expect("r", restored.required)
    }

    @TestCase
    func oneMarkerCarriesBothOptions() {
        // act
        let dms = DerivedRenamedAndSkipped().serialize().asStructOrThrow()
        let restored = DerivedRenamedAndSkipped.deserialize(DataModelStruct().add(field("textDocument", "file:///a.cj")))

        // assert
        @Expect(dms.getOrNone("textDocument").isNone())
        @Expect(Some("file:///a.cj"), restored.document)
    }
}

@DeriveExt[Serializable]
@Derive[Equatable]
enum DerivedBaseTypes {
    | @DeriveExtSerializable[value: "URI"]
    Uri
    | @DeriveExtSerializable[value: "integer"]
    Numeric
    | Boolean
}

@DeriveExt[Serializable]
@Derive[Equatable]
enum DerivedSeverity {
    | @DeriveExtSerializable[value: 1]
    Fatal
    | @DeriveExtSerializable[value: 2]
    Warn
}

/**
 * A closed enumeration open to values it does not know; `Equatable` compares the payload too.
 */
@DeriveExt[Serializable]
@Derive[Equatable]
enum DerivedSymbolKind {
    | @DeriveExtSerializable[value: 1]
    File
    | @DeriveExtSerializable[value: 2]
    Module
    | @DeriveExtSerializable[other]
    Unknown(UInt32)
}

@DeriveExt[Serializable]
@Derive[Equatable]
enum DerivedMarkupKind {
    | @DeriveExtSerializable[value: "plaintext"]
    PlainText
    | @DeriveExtSerializable[other]
    Unknown(String)
}

@DeriveExt[Serializable]
@Derive[Equatable]
enum DerivedErrorCode {
    | @DeriveExtSerializable[value: -32700]
    ParseError
    | @DeriveExtSerializable[value: -32601]
    MethodNotFound
    | @DeriveExtSerializable[value: 1]
    Custom
}

@DeriveExt[Serializable]
@Derive[Equatable]
enum DerivedNarrowOrWide {
    | Narrow(Int32)
    | Wide(Int64)
}

@DeriveExt[Serializable]
@DeriveExtSerializable[tag: "kind", skipNone]
@Derive[Equatable]
enum DerivedTaggedPayload {
    | @DeriveExtSerializable[value: "note", payload: ["text", "detail"]]
    Note(String, ?String)
}

@DeriveExt[Serializable]
enum DerivedScalarOrList {
    | Single(String)
    | Many(Array<String>)
}

@DeriveExt[Serializable]
enum DerivedOneOrMany<T> {
    | One(T)
    | Several(Array<T>)
}

@DeriveExt[Serializable]
@DeriveExtSerializable[tag: "kind"]
@Derive[Equatable]
enum DerivedShape {
    | @DeriveExtSerializable[value: "circle", payload: ["radius"]]
    Circle(Int64)
    | @DeriveExtSerializable[value: "rect", payload: ["width", "height"]]
    Rect(Int64, Int64)
    | @DeriveExtSerializable[value: "point"]
    Point
}

@Test
class DeriveScalarEnumTest {
    @TestCase
    func aValuedVariantTravelsAsThatValueAndAPlainOneAsItsName() {
        // act & assert
        @Expect("URI", DerivedBaseTypes.Uri.serialize().asStringOrThrow())
        @Expect("integer", DerivedBaseTypes.Numeric.serialize().asStringOrThrow())
        @Expect("Boolean", DerivedBaseTypes.Boolean.serialize().asStringOrThrow())
        @Expect(DerivedBaseTypes.Numeric, DerivedBaseTypes.deserialize(DataModelString("integer")))
    }

    @TestCase
    func anIntegerEnumTravelsAsANumber() {
        // act & assert
        @Expect(2, DerivedSeverity.Warn.serialize().asIntOrThrow())
        @Expect(DerivedSeverity.Fatal, DerivedSeverity.deserialize(DataModelInt(1)))
    }

    @TestCase
    func aNegativeValueSurvivesTheTwoTokensItIsMadeOf() {
        // act & assert
        @Expect(-32700, DerivedErrorCode.ParseError.serialize().asIntOrThrow())
        @Expect(DerivedErrorCode.MethodNotFound, DerivedErrorCode.deserialize(DataModelInt(-32601)))
    }

    @TestCase
    func anUnknownValueThrowsNamingIt() {
        // act
        let e = @AssertThrows[DataModelException](DerivedBaseTypes.deserialize(DataModelString("nope")))

        // assert
        @Expect("unexpected `DerivedBaseTypes` value: nope", e.message)
    }
}

@Test
class DeriveOtherVariantTest {
    @TestCase
    func aKnownValueStillReadsAsItsVariant() {
        // act & assert
        @Expect(DerivedSymbolKind.Module, DerivedSymbolKind.deserialize(DataModelInt(2)))
        @Expect(DerivedMarkupKind.PlainText, DerivedMarkupKind.deserialize(DataModelString("plaintext")))
    }

    @TestCase
    func anUnknownValueIsKeptAndWrittenBack() {
        // act
        let symbol = DerivedSymbolKind.deserialize(DataModelInt(27))
        let markup = DerivedMarkupKind.deserialize(DataModelString("asciidoc"))

        // assert
        @Expect(DerivedSymbolKind.Unknown(27), symbol)
        @Expect(27, symbol.serialize().asIntOrThrow())
        @Expect(DerivedMarkupKind.Unknown("asciidoc"), markup)
        @Expect("asciidoc", markup.serialize().asStringOrThrow())
    }

    @TestCase
    func anUnknownValueOutsideThePayloadTypeThrows() {
        // act & assert
        @AssertThrows(DerivedSymbolKind.deserialize(DataModelInt(-1)))
    }

    @TestCase
    func aValueOfTheWrongKindStillThrows() {
        // act & assert
        @AssertThrows[DataModelException](DerivedSymbolKind.deserialize(DataModelString("1")))
        @AssertThrows[DataModelException](DerivedMarkupKind.deserialize(DataModelInt(1)))
    }
}

@Test
class DeriveUntaggedEnumTest {
    @TestCase
    func theVariantIsWhicheverOneTheValueReadsAs() {
        // act
        let single = DerivedScalarOrList.deserialize(DataModelString("one"))
        let many = DerivedScalarOrList.deserialize(
            DataModelSeq(ArrayList<DataModel>([DataModelString("a"), DataModelString("b")])))

        // assert
        @Expect(match (single) {
            case Single(s) => s == "one"
            case _ => false
        })
        @Expect(match (many) {
            case Many(items) => items == ["a", "b"]
            case _ => false
        })
    }

    @TestCase
    func aVariantSerializesAsItsPayloadAlone() {
        // act & assert
        @Expect("one", DerivedScalarOrList.Single("one").serialize().asStringOrThrow())
        @Expect(DerivedScalarOrList.Many(["a"]).serialize() is DataModelSeq)
    }

    @TestCase
    func aVariantThatOverflowsGivesWayToTheNextOne() {
        // act & assert
        @Expect(DerivedNarrowOrWide.Wide(5_000_000_000), DerivedNarrowOrWide.deserialize(DataModelInt(5_000_000_000)))
        @Expect(DerivedNarrowOrWide.Narrow(7), DerivedNarrowOrWide.deserialize(DataModelInt(7)))
    }

    @TestCase
    func aValueMatchingNoVariantThrows() {
        // act
        let e = @AssertThrows[DataModelException](DerivedScalarOrList.deserialize(DataModelInt(1)))

        // assert
        @Expect("no `DerivedScalarOrList` variant matched the value", e.message)
    }

    @TestCase
    func aGenericUntaggedEnumRoundTrips() {
        // act
        let one = DerivedOneOrMany<String>.deserialize(DerivedOneOrMany.One("x").serialize())
        let several = DerivedOneOrMany<String>.deserialize(DerivedOneOrMany.Several(["x", "y"]).serialize())

        // assert
        @Expect(match (one) {
            case One(s) => s == "x"
            case _ => false
        })
        @Expect(match (several) {
            case Several(items) => items == ["x", "y"]
            case _ => false
        })
    }
}

@Test
class DeriveTaggedEnumTest {
    @TestCase
    func thePayloadTravelsBesideTheTag() {
        // act
        let dms = DerivedShape.Rect(3, 4).serialize().asStructOrThrow()

        // assert
        @Expect("rect", dms.getOrThrow("kind").asStringOrThrow())
        @Expect(3, dms.getOrThrow("width").asIntOrThrow())
        @Expect(4, dms.getOrThrow("height").asIntOrThrow())
    }

    @TestCase
    func aVariantWithoutPayloadIsTheTagAlone() {
        // act
        let dms = DerivedShape.Point.serialize().asStructOrThrow()

        // assert
        @Expect("point", dms.getOrThrow("kind").asStringOrThrow())
        @Expect(1, dms.getFields().size)
    }

    @TestCase[shape in [DerivedShape.Circle(5), DerivedShape.Rect(3, 4), DerivedShape.Point]]
    func everyShapeRoundTrips(shape: DerivedShape) {
        // act & assert
        @Expect(shape, DerivedShape.deserialize(shape.serialize()))
    }

    @TestCase
    func anOptionalPayloadFollowsTheSameRulesAsAField() {
        // act
        let dms = DerivedTaggedPayload.Note("hello", None).serialize().asStructOrThrow()

        // assert
        @Expect(dms.getOrNone("detail").isNone())
        @Expect("hello", dms.getOrThrow("text").asStringOrThrow())
        @Expect(DerivedTaggedPayload.Note("hello", None), DerivedTaggedPayload.deserialize(dms))
    }

    @TestCase
    func anUnknownTagThrowsNamingIt() {
        // arrange
        let dms = DataModelStruct().add(field("kind", "hexagon"))

        // act
        let e = @AssertThrows[DataModelException](DerivedShape.deserialize(dms))

        // assert
        @Expect("unexpected `DerivedShape` kind: hexagon", e.message)
    }
}

@Test
class DeriveTransparentTest {
    @TestCase
    func aTransparentStructTravelsAsItsOnlyField() {
        // act & assert
        @Expect(-32700, DerivedOpenCode.PARSE_ERROR.serialize().asIntOrThrow())
        @Expect("refactor", DerivedOpenKind(value: "refactor").serialize().asStringOrThrow())
    }

    @TestCase
    func aValueOutsideTheKnownConstantsRoundTrips() {
        // act & assert
        @Expect(DerivedOpenCode(-1), DerivedOpenCode.deserialize(DataModelInt(-1)))
        @Expect("x", DerivedOpenKind.deserialize(DataModelString("x")).value)
    }

    @TestCase
    func aValueTheFieldCannotHoldThrows() {
        // act & assert
        @AssertThrows[DataModelException](DerivedOpenCode.deserialize(DataModelString("-1")))
        @AssertThrows(DerivedOpenUnsigned.deserialize(DataModelInt(-1)))
    }
}

@Test
class DeriveTaggedStructTest {
    @TestCase
    func theTagIsWrittenAheadOfTheFields() {
        // act
        let fields = DerivedCreateFile(uri: "file:///a").serialize().asStructOrThrow().getFields()

        // assert
        @Expect(2, fields.size)
        @Expect("kind", fields[0].getName())
        @Expect("create", fields[0].getData().asStringOrThrow())
        @Expect("uri", fields[1].getName())
    }

    @TestCase
    func aTaggedStructRoundTrips() {
        // act
        let restored = DerivedDeleteFile.deserialize(DerivedDeleteFile(uri: "file:///a", recursive: true).serialize())

        // assert
        @Expect("file:///a", restored.uri)
        @Expect(Some(true), restored.recursive)
    }

    @TestCase
    func aForeignOrAbsentTagThrows() {
        // arrange
        let otherTag = DataModelStruct().add(field("kind", "delete")).add(field("uri", "file:///a"))
        let absent = DataModelStruct().add(field("uri", "file:///a"))

        // act
        let onOtherTag = @AssertThrows[DataModelException](DerivedCreateFile.deserialize(otherTag))
        let onAbsent = @AssertThrows[DataModelException](DerivedCreateFile.deserialize(absent))

        // assert
        @Expect("unexpected `DerivedCreateFile` kind: delete", onOtherTag.message)
        @Expect("required field \"kind\" is absent", onAbsent.message)
    }

    @TestCase
    func theTagPicksTheVariantOfAnUntaggedUnion() {
        // arrange - both structs read `{"uri"}` alike; only the tag keeps the first from taking it
        let dms = DataModelStruct().add(field("kind", "delete")).add(field("uri", "file:///a"))

        // act
        let restored = DerivedFileOperation.deserialize(dms)

        // assert
        @Expect(match (restored) {
            case Delete(op) => op.uri == "file:///a"
            case _ => false
        })
    }
}
