package stdxx

import std.deriving.*
import std.unittest.*
import std.unittest.testmacro.*
import std.collection.*
import stdx.serialization.serialization.*
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
 * The shape `lsp_codegen` emits for an open enumeration: marker between the two derives.
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
        let described = DerivedAndDescribed(name: "cjls")

        // act & assert
        @Expect("cjls", described.serialize().asStructOrThrow().getOrThrow("name").asStringOrThrow())
        @Expect("DerivedAndDescribed(name: cjls)", described.toString())
    }
}

@Test
class DeriveSerializableNullabilityTest {
    @TestCase
    func anAbsentOptionalIsWrittenAsNull() {
        // arrange
        let shapes = DerivedShapes(required: "r", nullable: Value("n"))

        // act
        let dms = shapes.serialize().asStructOrThrow()

        // assert
        @Assert(dms.getOrThrow("optional") is DataModelNull)
        @Assert(dms.getOrThrow("optionalNullable") is DataModelNull)
    }

    @TestCase
    func aPresentOptionalIsWritten() {
        // arrange
        let shapes = DerivedShapes(required: "r", nullable: Value("n"), optional: "o")

        // act
        let dms = shapes.serialize().asStructOrThrow()

        // assert
        @Expect("o", dms.getOrThrow("optional").asStringOrThrow())
    }

    @TestCase
    func aNullNullableIsAlwaysWritten() {
        // arrange
        let shapes = DerivedShapes(required: "r", nullable: Null)

        // act
        let dms = shapes.serialize().asStructOrThrow()

        // assert
        @Assert(dms.getOrThrow("nullable") is DataModelNull)
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
        @Assert(restored.optional.isNone())
        @Assert(restored.nullable.isNull())
    }

    @TestCase
    func anOptionalNullableTellsAbsentFromNull() {
        // arrange
        let present = DataModelStruct()
            .add(field("required", "r"))
            .add(Field("nullable", DataModelNull()))
            .add(Field("optionalNullable", DataModelNull()))
        let absent = DataModelStruct().add(field("required", "r")).add(Field("nullable", DataModelNull()))

        // act
        let restoredNull = DerivedShapes.deserialize(present)
        let restoredAbsent = DerivedShapes.deserialize(absent)

        // assert
        @Assert(restoredNull.optionalNullable.getOrThrow().isNull())
        @Assert(restoredAbsent.optionalNullable.isNone())
    }
}

@Test
class DeriveSkipNoneTest {
    @TestCase
    func onTheTypeItOmitsEveryNoneField() {
        // act
        let dms = DerivedSkipped(required: "r").serialize().asStructOrThrow()

        // assert
        @Assert(dms.getOrNone("optional").isNone())
        @Assert(dms.getOrNone("optionalNullable").isNone())
        @Expect("r", dms.getOrThrow("required").asStringOrThrow())
    }

    @TestCase
    func onTheTypeItStillWritesAnExplicitNull() {
        // act
        let dms = DerivedSkipped(required: "r", optionalNullable: Null).serialize().asStructOrThrow()

        // assert
        @Assert(dms.getOrThrow("optionalNullable") is DataModelNull)
    }

    @TestCase
    func onASingleFieldItLeavesTheRestAlone() {
        // act
        let dms = DerivedPartlySkipped().serialize().asStructOrThrow()

        // assert
        @Assert(dms.getOrNone("skipped").isNone())
        @Assert(dms.getOrThrow("kept") is DataModelNull)
    }

    @TestCase
    func modifiersDoNotHideTheMarkerOrTheFields() {
        // act
        let dms = DerivedPublicSkipped(required: "r").serialize().asStructOrThrow()
        let restored = DerivedPublicSkipped.deserialize(dms)

        // assert
        @Assert(dms.getOrNone("optional").isNone())
        @Expect("r", restored.required)
    }

    @TestCase
    func oneMarkerCarriesBothOptions() {
        // act
        let dms = DerivedRenamedAndSkipped().serialize().asStructOrThrow()
        let restored = DerivedRenamedAndSkipped.deserialize(DataModelStruct().add(field("textDocument", "file:///a.cj")))

        // assert
        @Assert(dms.getOrNone("textDocument").isNone())
        @Expect("file:///a.cj", restored.document ?? "<none>")
    }

    @TestCase
    func omittedFieldsRoundTrip() {
        // act
        let restored = DerivedSkipped.deserialize(DerivedSkipped(required: "r").serialize())

        // assert
        @Expect("r", restored.required)
        @Assert(restored.optional.isNone())
        @Assert(restored.optionalNullable.isNone())
    }
}

@Test
class DeriveSerializableNamingTest {
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
        @Assert(dms.getOrNone("document").isNone())
        @Expect("file:///a.cj", restored.document)
        @Expect("cangjie", restored.`type`)
    }
}

@DeriveExt[Serializable]
enum DerivedBaseTypes {
    | @DeriveExtSerializable[value: "URI"]
    Uri
    | @DeriveExtSerializable[value: "integer"]
    Numeric
    | Boolean
}

@DeriveExt[Serializable]
enum DerivedSeverity {
    | @DeriveExtSerializable[value: 1]
    Fatal
    | @DeriveExtSerializable[value: 2]
    Warn
}

/**
 * The shape `lsp_codegen` emits for a closed enumeration, `@Derive` included: the payload is what
 * `Equatable` compares on.
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
enum DerivedErrorCode {
    | @DeriveExtSerializable[value: -32700]
    ParseError
    | @DeriveExtSerializable[value: -32601]
    MethodNotFound
    | @DeriveExtSerializable[value: 1]
    Custom
}

@DeriveExt[Serializable]
enum DerivedNarrowOrWide {
    | Narrow(Int32)
    | Wide(Int64)
}

@DeriveExt[Serializable]
@DeriveExtSerializable[tag: "kind", skipNone]
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
    }

    @TestCase
    func aStringEnumRoundTrips() {
        // act
        let restored = DerivedBaseTypes.deserialize(DataModelString("integer"))

        // assert
        @Assert(matchesNumeric(restored))
    }

    @TestCase
    func anIntegerEnumTravelsAsANumber() {
        // act
        let dm = DerivedSeverity.Warn.serialize()
        let restored = DerivedSeverity.deserialize(DataModelInt(1))

        // assert
        @Expect(2, dm.asIntOrThrow())
        @Assert(matchesFatal(restored))
    }

    @TestCase
    func aNegativeValueSurvivesTheTwoTokensItIsMadeOf() {
        // act
        let dm = DerivedErrorCode.ParseError.serialize()
        let restored = DerivedErrorCode.deserialize(DataModelInt(-32601))

        // assert
        @Expect(-32700, dm.asIntOrThrow())
        @Assert(matchesMethodNotFound(restored))
    }

    @TestCase
    func anUnknownValueThrowsNamingIt() {
        // act
        let e = @AssertThrows[DataModelException](DerivedBaseTypes.deserialize(DataModelString("nope")))

        // assert
        @Expect("unexpected `DerivedBaseTypes` value: nope", e.message)
    }

    private static func matchesNumeric(value: DerivedBaseTypes): Bool {
        match (value) {
            case Numeric => true
            case _ => false
        }
    }

    private static func matchesMethodNotFound(value: DerivedErrorCode): Bool {
        match (value) {
            case MethodNotFound => true
            case _ => false
        }
    }

    private static func matchesFatal(value: DerivedSeverity): Bool {
        match (value) {
            case Fatal => true
            case _ => false
        }
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
        @Expect("single:one", describe(single))
        @Expect("many:a,b", describe(many))
    }

    @TestCase
    func aVariantSerializesAsItsPayloadAlone() {
        // act & assert
        @Expect("one", DerivedScalarOrList.Single("one").serialize().asStringOrThrow())
        @Assert(DerivedScalarOrList.Many(["a"]).serialize() is DataModelSeq)
    }

    @TestCase
    func aVariantThatOverflowsGivesWayToTheNextOne() {
        // act
        let wide = DerivedNarrowOrWide.deserialize(DataModelInt(5_000_000_000))
        let narrow = DerivedNarrowOrWide.deserialize(DataModelInt(7))

        // assert
        @Expect("wide:5000000000", describeWidth(wide))
        @Expect("narrow:7", describeWidth(narrow))
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
        @Expect("one:x", describeOneOrMany(one))
        @Expect("several:x,y", describeOneOrMany(several))
    }

    @TestCase
    func aVariantWithSeveralPayloadsIsReadFromAnArrayOfThatLength() {
        // arrange
        let pair = DataModelSeq(ArrayList<DataModel>([DataModelInt(3), DataModelInt(7)]))

        // act & assert
        @Expect("offsets:3..7", describeLabel(DerivedLabel.deserialize(pair)))
        @Expect("text:x", describeLabel(DerivedLabel.deserialize(DataModelString("x"))))
    }

    @TestCase
    func aVariantWithSeveralPayloadsIsWrittenAsAnArray() {
        // act
        let items = DerivedLabel.Offsets(3, 7).serialize().asSeqOrThrow().getItems()

        // assert
        @Assert(2, items.size)
        @Expect(3, items[0].asIntOrThrow())
        @Expect(7, items[1].asIntOrThrow())
    }

    @TestCase
    func anArrayOfAnotherLengthMatchesNoTupleVariant() {
        // arrange
        let triple = DataModelSeq(ArrayList<DataModel>([DataModelInt(1), DataModelInt(2), DataModelInt(3)]))

        // act & assert
        @AssertThrows[DataModelException](DerivedLabel.deserialize(triple))
    }

    @TestCase
    func aTupleWithAnUnreadableItemGivesWayToTheNextOne() {
        // arrange
        let negative = DataModelSeq(ArrayList<DataModel>([DataModelInt(-1), DataModelInt(2)]))

        // act & assert
        @Expect("signed:-1..2", describeLabel(DerivedLabel.deserialize(negative)))
    }

    private static func describeLabel(value: DerivedLabel): String {
        match (value) {
            case Text(s) => "text:${s}"
            case Offsets(start, end) => "offsets:${start}..${end}"
            case Signed(start, end) => "signed:${start}..${end}"
        }
    }

    private static func describeWidth(value: DerivedNarrowOrWide): String {
        match (value) {
            case Narrow(n) => "narrow:${n}"
            case Wide(n) => "wide:${n}"
        }
    }

    private static func describe(value: DerivedScalarOrList): String {
        match (value) {
            case Single(s) => "single:${s}"
            case Many(items) => "many:${String.join(items, delimiter: ",")}"
        }
    }

    private static func describeOneOrMany(value: DerivedOneOrMany<String>): String {
        match (value) {
            case One(s) => "one:${s}"
            case Several(items) => "several:${String.join(items, delimiter: ",")}"
        }
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

    @TestCase
    func everyShapeRoundTrips() {
        // act & assert
        @Expect("circle:5", describe(DerivedShape.deserialize(DerivedShape.Circle(5).serialize())))
        @Expect("rect:3x4", describe(DerivedShape.deserialize(DerivedShape.Rect(3, 4).serialize())))
        @Expect("point", describe(DerivedShape.deserialize(DerivedShape.Point.serialize())))
    }

    @TestCase
    func anOptionalPayloadFollowsTheSameRulesAsAField() {
        // act
        let dms = DerivedTaggedPayload.Note("hello", None).serialize().asStructOrThrow()
        let restored = DerivedTaggedPayload.deserialize(dms)

        // assert
        @Assert(dms.getOrNone("detail").isNone())
        @Expect("hello", dms.getOrThrow("text").asStringOrThrow())
        @Assert(describeNote(restored) == "hello/<none>")
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

    private static func describeNote(value: DerivedTaggedPayload): String {
        match (value) {
            case Note(text, detail) => "${text}/${detail ?? "<none>"}"
        }
    }

    private static func describe(value: DerivedShape): String {
        match (value) {
            case Circle(r) => "circle:${r}"
            case Rect(w, h) => "rect:${w}x${h}"
            case Point => "point"
        }
    }
}

@Test
class DeriveTransparentTest {
    @TestCase
    func aTransparentStructTravelsAsItsOnlyField() {
        // act
        let dm = DerivedOpenCode.PARSE_ERROR.serialize()

        // assert
        @Expect(-32700, dm.asIntOrThrow())
    }

    @TestCase
    func aValueOutsideTheKnownConstantsRoundTrips() {
        // act
        let restored = DerivedOpenCode.deserialize(DataModelInt(-1))

        // assert
        @Expect(-1i32, restored.value)
        @Expect(DerivedOpenCode(-1), restored)
    }

    @TestCase
    func anUnsignedFieldRoundTrips() {
        // act
        let restored = DerivedOpenUnsigned.deserialize(DerivedOpenUnsigned(7).serialize())

        // assert
        @Expect(7u32, restored.value)
    }

    @TestCase
    func aNamedFieldRoundTrips() {
        // act
        let dm = DerivedOpenKind(value: "refactor").serialize()
        let restored = DerivedOpenKind.deserialize(dm)

        // assert
        @Expect("refactor", dm.asStringOrThrow())
        @Expect("refactor", restored.value)
    }

    @TestCase
    func aValueOfTheWrongKindThrows() {
        // act & assert
        @AssertThrows[DataModelException](DerivedOpenCode.deserialize(DataModelString("-1")))
    }

    @TestCase
    func aValueOutsideTheFieldTypeThrows() {
        // act & assert
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
    func aForeignTagThrowsNamingIt() {
        // arrange
        let dms = DataModelStruct().add(field("kind", "delete")).add(field("uri", "file:///a"))

        // act
        let e = @AssertThrows[DataModelException](DerivedCreateFile.deserialize(dms))

        // assert
        @Expect("unexpected `DerivedCreateFile` kind: delete", e.message)
    }

    @TestCase
    func anAbsentTagThrows() {
        // arrange
        let dms = DataModelStruct().add(field("uri", "file:///a"))

        // act
        let e = @AssertThrows[DataModelException](DerivedCreateFile.deserialize(dms))

        // assert
        @Expect("required field \"kind\" is absent", e.message)
    }

    /**
     * Both structs read `{"uri"}` alike - only the tag keeps the first variant from taking the other's
     * value.
     */
    @TestCase
    func theTagPicksTheVariantOfAnUntaggedUnion() {
        // arrange
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

@Test
class DeriveOtherVariantTest {
    @TestCase
    func aKnownValueStillReadsAsItsVariant() {
        // act & assert
        @Expect(DerivedSymbolKind.Module, DerivedSymbolKind.deserialize(DataModelInt(2)))
        @Expect(DerivedMarkupKind.PlainText, DerivedMarkupKind.deserialize(DataModelString("plaintext")))
    }

    @TestCase
    func anUnknownIntegerIsKeptAndWrittenBack() {
        // act
        let restored = DerivedSymbolKind.deserialize(DataModelInt(27))

        // assert
        @Expect(DerivedSymbolKind.Unknown(27), restored)
        @Expect(27, restored.serialize().asIntOrThrow())
    }

    @TestCase
    func anUnknownStringIsKeptAndWrittenBack() {
        // act
        let restored = DerivedMarkupKind.deserialize(DataModelString("asciidoc"))

        // assert
        @Expect(DerivedMarkupKind.Unknown("asciidoc"), restored)
        @Expect("asciidoc", restored.serialize().asStringOrThrow())
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
