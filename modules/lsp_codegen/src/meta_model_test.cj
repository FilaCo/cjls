package lsp_codegen

import std.collection.HashMap
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import stdx.encoding.json.*
import stdx.serialization.serialization.*
import stdxx.*

private func dmOf(json: String) {
    DataModel.fromJson(JsonValue.fromStr(json))
}

private func jsonOf(dm: DataModel) {
    dm.toJson().toString()
}

@Test
class MetaDataTest {
    @TestCase
    func deserializesVersion() {
        // arrange
        let json = "{\"version\":\"3.18.0\"}"

        // act
        let sut = MetaData.deserialize(dmOf(json))

        // assert
        @Expect("3.18.0", sut.version)
    }

    @TestCase
    func roundTrips() {
        // arrange
        let json = "{\"version\":\"3.17.0\"}"

        // act & assert
        assertSameJson(json, MetaData.deserialize(dmOf(json)).serialize())
    }

    @TestCase
    func absentVersionThrows() {
        // arrange
        let json = "{}"

        // act
        let e = @AssertThrows[DataModelException](MetaData.deserialize(dmOf(json)))

        // assert
        @Expect("required field \"version\" is absent", e.message)
    }
}

@Test
class BaseTypesTest {
    func wireOf(sut: BaseTypes): String {
        sut.serialize().asStringOrThrow()
    }

    @TestCase
    func variantsSerializeToTheirWireNames() {
        // act & assert
        @Expect("URI", wireOf(BaseTypes.Uri))
        @Expect("DocumentUri", wireOf(BaseTypes.DocumentUri))
        @Expect("integer", wireOf(BaseTypes.Integer))
        @Expect("uinteger", wireOf(BaseTypes.UInteger))
        @Expect("decimal", wireOf(BaseTypes.Decimal))
        @Expect("RegExp", wireOf(BaseTypes.RegExp))
        @Expect("string", wireOf(BaseTypes.String))
        @Expect("boolean", wireOf(BaseTypes.Boolean))
        @Expect("null", wireOf(BaseTypes.Null))
    }

    @TestCase[wire in [ "URI", "DocumentUri", "integer", "uinteger", "decimal", "RegExp", "string", "boolean", "null" ]]
    func wireNamesRoundTrip(wire: String) {
        // act & assert
        @Expect(wire, wireOf(BaseTypes.deserialize(DataModelString(wire))))
    }

    @TestCase
    func unknownNameThrows() {
        // act
        let e = @AssertThrows[DataModelException](BaseTypes.deserialize(DataModelString("float")))

        // assert
        @Expect("invalid `BaseTypes` value", e.message)
    }
}

@Test
class MessageDirectionTest {
    func wireOf(sut: MessageDirection): String {
        sut.serialize().asStringOrThrow()
    }

    @TestCase
    func variantsSerializeToTheirWireNames() {
        // act & assert
        @Expect("clientToServer", wireOf(MessageDirection.ClientToServer))
        @Expect("serverToClient", wireOf(MessageDirection.ServerToClient))
        @Expect("both", wireOf(MessageDirection.Both))
    }

    @TestCase[wire in [ "clientToServer", "serverToClient", "both" ]]
    func wireNamesRoundTrip(wire: String) {
        // act & assert
        @Expect(wire, wireOf(MessageDirection.deserialize(DataModelString(wire))))
    }

    @TestCase
    func unknownNameThrows() {
        // act
        let e = @AssertThrows[DataModelException](MessageDirection.deserialize(DataModelString("bidirectional")))

        // assert
        @Expect("invalid `MessageDirection` value", e.message)
    }
}

@Test
class MapKeyNameTest {
    func wireOf(sut: MapKeyName): String {
        sut.serialize().asStringOrThrow()
    }

    @TestCase
    func variantsSerializeToTheirWireNames() {
        // act & assert
        @Expect("URI", wireOf(MapKeyName.Uri))
        @Expect("DocumentUri", wireOf(MapKeyName.DocumentUri))
        @Expect("string", wireOf(MapKeyName.String))
        @Expect("integer", wireOf(MapKeyName.Integer))
    }

    @TestCase[wire in [ "URI", "DocumentUri", "string", "integer" ]]
    func wireNamesRoundTrip(wire: String) {
        // act & assert
        @Expect(wire, wireOf(MapKeyName.deserialize(DataModelString(wire))))
    }

    @TestCase
    func unknownNameThrows() {
        // act
        let e = @AssertThrows[DataModelException](MapKeyName.deserialize(DataModelString("decimal")))

        // assert
        @Expect("invalid `MapKeyName` value", e.message)
    }
}

@Test
class MapKeyTypeTest {
    @TestCase[json in [ "{\"kind\":\"base\",\"name\":\"string\"}", "{\"kind\":\"base\",\"name\":\"DocumentUri\"}", 
 "{\"kind\":\"reference\",\"name\":\"ChangeAnnotationIdentifier\"}" ]]
    func roundTrips(json: String) {
        // act & assert
        assertSameJson(json, MapKeyType.deserialize(dmOf(json)).serialize())
    }

    @TestCase
    func baseCarriesTheKeyName() {
        // arrange
        let json = "{\"kind\":\"base\",\"name\":\"integer\"}"

        // act
        let name = match (MapKeyType.deserialize(dmOf(json))) {
            case MapKeyType.Base(name) => name.serialize().asStringOrThrow()
            case _ => "not a base"
        }

        // assert
        @Expect("integer", name)
    }

    @TestCase
    func referenceCarriesTheTypeName() {
        // arrange
        let json = "{\"kind\":\"reference\",\"name\":\"ChangeAnnotationIdentifier\"}"

        // act
        let name = match (MapKeyType.deserialize(dmOf(json))) {
            case MapKeyType.Reference(name) => name
            case _ => "not a reference"
        }

        // assert
        @Expect("ChangeAnnotationIdentifier", name)
    }

    @TestCase
    func unknownKindThrows() {
        // arrange
        let json = "{\"kind\":\"literal\",\"name\":\"x\"}"

        // act
        let e = @AssertThrows[DataModelException](MapKeyType.deserialize(dmOf(json)))

        // assert
        @Expect("unexpected `kind` field value: \"literal\"", e.message)
    }

    @TestCase
    func absentKindThrows() {
        // arrange
        let json = "{\"name\":\"string\"}"

        // act
        let e = @AssertThrows[DataModelException](MapKeyType.deserialize(dmOf(json)))

        // assert
        @Expect("required field \"kind\" is absent", e.message)
    }
}

@Test
class TypeTest {
    static let literalJson = "{\"kind\":\"literal\",\"value\":{\"properties\":[{\"name\":\"start\",\"type\":{\"kind\":\"base\",\"name\":\"uinteger\"},\"optional\":false,\"proposed\":false}],\"proposed\":false}}"

    @TestCase[json in [ 
 "{\"kind\":\"base\",\"name\":\"string\"}", 
 "{\"kind\":\"reference\",\"name\":\"Position\"}", 
 "{\"kind\":\"array\",\"element\":{\"kind\":\"base\",\"name\":\"uinteger\"}}", 
 "{\"kind\":\"map\",\"key\":{\"kind\":\"base\",\"name\":\"DocumentUri\"},\"value\":{\"kind\":\"reference\",\"name\":\"TextEdit\"}}", 
 "{\"kind\":\"and\",\"items\":[{\"kind\":\"reference\",\"name\":\"A\"},{\"kind\":\"reference\",\"name\":\"B\"}]}", 
 "{\"kind\":\"or\",\"items\":[{\"kind\":\"reference\",\"name\":\"Location\"},{\"kind\":\"base\",\"name\":\"null\"}]}", 
 "{\"kind\":\"tuple\",\"items\":[{\"kind\":\"base\",\"name\":\"uinteger\"},{\"kind\":\"base\",\"name\":\"uinteger\"}]}", 
 "{\"kind\":\"stringLiteral\",\"value\":\"rename\"}", 
 "{\"kind\":\"integerLiteral\",\"value\":1}", 
 "{\"kind\":\"booleanLiteral\",\"value\":true}" 
 ]]
    func kindsRoundTrip(json: String) {
        // act & assert
        assertSameJson(json, Type.deserialize(dmOf(json)).serialize())
    }

    @TestCase
    func literalRoundTrips() {
        // act & assert - a nested structure literal, spelled with the defaults the serializer always writes
        assertSameJson(literalJson, Type.deserialize(dmOf(literalJson)).serialize())
    }

    @TestCase
    func baseCarriesItsBaseType() {
        // act
        let name = match (Type.deserialize(dmOf("{\"kind\":\"base\",\"name\":\"decimal\"}"))) {
            case Type.Base(baseType) => baseType.serialize().asStringOrThrow()
            case _ => "not a base"
        }

        // assert
        @Expect("decimal", name)
    }

    @TestCase
    func arrayCarriesItsElementType() {
        // arrange
        let json = "{\"kind\":\"array\",\"element\":{\"kind\":\"reference\",\"name\":\"Diagnostic\"}}"

        // act
        let element = match (Type.deserialize(dmOf(json))) {
            case Type.Array(element) => jsonOf(element.serialize())
            case _ => "not an array"
        }

        // assert
        @Expect("{\"kind\":\"reference\",\"name\":\"Diagnostic\"}", element)
    }

    @TestCase
    func mapCarriesBothKeyAndValue() {
        // arrange
        let json = "{\"kind\":\"map\",\"key\":{\"kind\":\"base\",\"name\":\"string\"},\"value\":{\"kind\":\"base\",\"name\":\"integer\"}}"

        // act
        let (key, value) = match (Type.deserialize(dmOf(json))) {
            case Type.Map(key, value) => (jsonOf(key.serialize()), jsonOf(value.serialize()))
            case _ => ("not a map", "not a map")
        }

        // assert
        @Expect("{\"kind\":\"base\",\"name\":\"string\"}", key)
        @Expect("{\"kind\":\"base\",\"name\":\"integer\"}", value)
    }

    @TestCase
    func orCarriesEveryItem() {
        // arrange
        let json = "{\"kind\":\"or\",\"items\":[{\"kind\":\"reference\",\"name\":\"A\"},{\"kind\":\"reference\",\"name\":\"B\"},{\"kind\":\"base\",\"name\":\"null\"}]}"

        // act
        let count = match (Type.deserialize(dmOf(json))) {
            case Type.Or(items) => items.size
            case _ => -1
        }

        // assert
        @Expect(3, count)
    }

    @TestCase
    func integerLiteralCarriesItsValue() {
        // act
        let value = match (Type.deserialize(dmOf("{\"kind\":\"integerLiteral\",\"value\":-7}"))) {
            case Type.IntegerLiteral(value) => value
            case _ => 0
        }

        // assert
        @Expect(-7, value)
    }

    @TestCase
    func booleanLiteralCarriesItsValue() {
        // act
        let value = match (Type.deserialize(dmOf("{\"kind\":\"booleanLiteral\",\"value\":false}"))) {
            case Type.BooleanLiteral(value) => value
            case _ => true
        }

        // assert
        @Expect(false, value)
    }

    @TestCase
    func nestedTypesAreDeserializedRecursively() {
        // arrange - array of or-of-references
        let json = "{\"kind\":\"array\",\"element\":{\"kind\":\"or\",\"items\":[{\"kind\":\"reference\",\"name\":\"A\"},{\"kind\":\"reference\",\"name\":\"B\"}]}}"

        // act & assert
        assertSameJson(json, Type.deserialize(dmOf(json)).serialize())
    }

    @TestCase
    func unknownKindThrows() {
        // act
        let e = @AssertThrows[DataModelException](Type.deserialize(dmOf("{\"kind\":\"struct\"}")))

        // assert
        @Expect("unknown \"kind\": \"struct\"", e.message)
    }

    @TestCase
    func absentKindThrows() {
        // act
        let e = @AssertThrows[DataModelException](Type.deserialize(dmOf("{\"name\":\"string\"}")))

        // assert
        @Expect("required field \"kind\" is absent", e.message)
    }

    @TestCase
    func absentPayloadThrows() {
        // act - the discriminator is there, the payload the variant needs is not
        let e = @AssertThrows[DataModelException](Type.deserialize(dmOf("{\"kind\":\"array\"}")))

        // assert
        @Expect("required field \"element\" is absent", e.message)
    }
}

@Test
class OneOrManyTest {
    @TestCase
    func oneSerializesToTheUnderlyingValue() {
        // arrange
        let sut = OneOrMany<Type>.One(Type.Reference("Position"))

        // act & assert
        assertSameJson("{\"kind\":\"reference\",\"name\":\"Position\"}", sut.serialize())
    }

    @TestCase
    func manySerializesToAnArray() {
        // arrange
        let sut = OneOrMany<Type>.Many([Type.Reference("A"), Type.Reference("B")])

        // act & assert
        assertSameJson("[{\"kind\":\"reference\",\"name\":\"A\"},{\"kind\":\"reference\",\"name\":\"B\"}]",
            sut.serialize())
    }

    @TestCase
    func objectDeserializesToOne() {
        // arrange
        let json = "{\"kind\":\"reference\",\"name\":\"Position\"}"

        // act
        let sut = OneOrMany<Type>.deserialize(dmOf(json))

        // assert
        let name = match (sut) {
            case OneOrMany<Type>.One(Type.Reference(name)) => name
            case _ => "not a single reference"
        }
        @Expect("Position", name)
    }

    @TestCase
    func arrayDeserializesToMany() {
        // arrange
        let json = "[{\"kind\":\"reference\",\"name\":\"A\"},{\"kind\":\"reference\",\"name\":\"B\"}]"

        // act
        let sut = OneOrMany<Type>.deserialize(dmOf(json))

        // assert
        let count = match (sut) {
            case OneOrMany<Type>.Many(items) => items.size
            case _ => -1
        }
        @Expect(2, count)
    }

    @TestCase
    func emptyArrayDeserializesToEmptyMany() {
        // act
        let sut = OneOrMany<Type>.deserialize(dmOf("[]"))

        // assert
        let count = match (sut) {
            case OneOrMany<Type>.Many(items) => items.size
            case _ => -1
        }
        @Expect(0, count)
    }

    @TestCase[json in [ "{\"kind\":\"reference\",\"name\":\"Position\"}", 
 "[{\"kind\":\"reference\",\"name\":\"A\"},{\"kind\":\"base\",\"name\":\"string\"}]" ]]
    func roundTrips(json: String) {
        // act & assert
        assertSameJson(json, OneOrMany<Type>.deserialize(dmOf(json)).serialize())
    }
}

@Test
class PropertyTest {
    @TestCase
    func absentFieldsStayAbsentRatherThanDefaulting() {
        // arrange - the flags carry the document's own tri-state; collapsing an absent
        // key to `false` is lowering's job, not the parser's
        let json = "{\"name\":\"uri\",\"type\":{\"kind\":\"base\",\"name\":\"DocumentUri\"}}"

        // act
        let sut = Property.deserialize(dmOf(json))

        // assert
        @Expect("uri", sut.name)
        @Assert(sut.optional.isNone())
        @Assert(sut.proposed.isNone())
        @Assert(sut.documentation.isNone())
        @Assert(sut.since.isNone())
        @Assert(sut.sinceTags.isNone())
        @Assert(sut.deprecated.isNone())
    }

    @TestCase
    func optionalAndProposedAreRead() {
        // arrange
        let json = "{\"name\":\"uri\",\"type\":{\"kind\":\"base\",\"name\":\"string\"},\"optional\":true,\"proposed\":true}"

        // act
        let sut = Property.deserialize(dmOf(json))

        // assert
        @Expect(true, sut.optional.getOrThrow())
        @Expect(true, sut.proposed.getOrThrow())
    }

    @TestCase
    func serializeOmitsEveryAbsentField() {
        // arrange
        let sut = Property(name: "uri", `type`: Type.Base(BaseTypes.DocumentUri))

        // act & assert - only the two required keys; an absent flag is never written as
        // `false`, which is what keeps the shipped meta model a lossless round trip
        assertSameJson("{\"name\":\"uri\",\"type\":{\"kind\":\"base\",\"name\":\"DocumentUri\"}}", sut.serialize())
    }

    @TestCase
    func serializeKeepsAnExplicitFalseApartFromAnAbsentFlag() {
        // arrange - the distinction `?Bool` exists to preserve
        let sut = Property(name: "uri", `type`: Type.Base(BaseTypes.DocumentUri), optional: false)

        // act & assert
        assertSameJson("{\"name\":\"uri\",\"type\":{\"kind\":\"base\",\"name\":\"DocumentUri\"},\"optional\":false}",
            sut.serialize())
    }

    @TestCase
    func documentationAndSinceTagsRoundTrip() {
        // arrange
        let json = "{\"name\":\"uri\",\"type\":{\"kind\":\"base\",\"name\":\"string\"},\"optional\":true,\"proposed\":false,\"documentation\":\"The uri.\",\"since\":\"3.17.0\",\"sinceTags\":[\"proposed\"],\"deprecated\":\"use `textDocument`\"}"

        // act
        let sut = Property.deserialize(dmOf(json))

        // assert
        @Expect("The uri.", sut.documentation.getOrThrow())
        @Expect("3.17.0", sut.since.getOrThrow())
        @Expect(1, sut.sinceTags.getOrThrow().size)
        @Expect("proposed", sut.sinceTags.getOrThrow()[0])
        @Expect("use `textDocument`", sut.deprecated.getOrThrow())
        assertSameJson(json, sut.serialize())
    }

    @TestCase
    func absentNameThrows() {
        // arrange
        let json = "{\"type\":{\"kind\":\"base\",\"name\":\"string\"}}"

        // act
        let e = @AssertThrows[DataModelException](Property.deserialize(dmOf(json)))

        // assert
        @Expect("required field \"name\" is absent", e.message)
    }

    @TestCase
    func absentTypeThrows() {
        // arrange
        let json = "{\"name\":\"uri\"}"

        // act
        let e = @AssertThrows[DataModelException](Property.deserialize(dmOf(json)))

        // assert
        @Expect("required field \"type\" is absent", e.message)
    }
}

@Test
class StructureLiteralTest {
    @TestCase
    func emptyPropertiesAreAllowed() {
        // arrange
        let json = "{\"properties\":[]}"

        // act
        let sut = StructureLiteral.deserialize(dmOf(json))

        // assert
        @Expect(0, sut.properties.size)
        @Assert(sut.proposed.isNone())
    }

    @TestCase
    func propertiesAreDeserialized() {
        // arrange
        let json = "{\"properties\":[{\"name\":\"start\",\"type\":{\"kind\":\"base\",\"name\":\"uinteger\"}},{\"name\":\"end\",\"type\":{\"kind\":\"base\",\"name\":\"uinteger\"}}]}"

        // act
        let sut = StructureLiteral.deserialize(dmOf(json))

        // assert
        @Expect(2, sut.properties.size)
        @Expect("start", sut.properties[0].name)
        @Expect("end", sut.properties[1].name)
    }

    @TestCase
    func roundTrips() {
        // arrange
        let json = "{\"properties\":[{\"name\":\"start\",\"type\":{\"kind\":\"base\",\"name\":\"uinteger\"},\"optional\":false,\"proposed\":false}],\"proposed\":true,\"since\":\"3.18.0\"}"

        // act & assert
        assertSameJson(json, StructureLiteral.deserialize(dmOf(json)).serialize())
    }

    @TestCase
    func absentPropertiesThrows() {
        // act
        let e = @AssertThrows[DataModelException](StructureLiteral.deserialize(dmOf("{}")))

        // assert
        @Expect("required field \"properties\" is absent", e.message)
    }
}

@Test
class EnumerationEntryTest {
    @TestCase
    func integerValueIsRead() {
        // arrange
        let json = "{\"name\":\"Error\",\"value\":1}"

        // act
        let sut = EnumerationEntry.deserialize(dmOf(json))

        // assert
        @Expect("Error", sut.name)
        @Expect(IntegerOrString.Integer(1), sut.value)
    }

    @TestCase
    func stringValueIsRead() {
        // arrange
        let json = "{\"name\":\"Created\",\"value\":\"created\"}"

        // act
        let sut = EnumerationEntry.deserialize(dmOf(json))

        // assert
        @Expect(IntegerOrString.String("created"), sut.value)
    }

    @TestCase[json in [ "{\"name\":\"Error\",\"value\":1,\"proposed\":false}", 
 "{\"name\":\"Created\",\"value\":\"created\",\"proposed\":false,\"documentation\":\"A created file.\"}" ]]
    func roundTrips(json: String) {
        // act & assert
        assertSameJson(json, EnumerationEntry.deserialize(dmOf(json)).serialize())
    }

    @TestCase
    func absentValueThrows() {
        // act
        let e = @AssertThrows[DataModelException](EnumerationEntry.deserialize(dmOf("{\"name\":\"Error\"}")))

        // assert
        @Expect("required field \"value\" is absent", e.message)
    }

    @TestCase
    func nonIntegerNonStringValueThrows() {
        // act
        let e = @AssertThrows[DataModelException](
            EnumerationEntry.deserialize(dmOf("{\"name\":\"Error\",\"value\":true}")))

        // assert
        @Expect("expected integer or string", e.message)
    }
}

@Test
class EnumerationTypeTest {
    func wireOf(sut: EnumerationType): String {
        jsonOf(sut.serialize())
    }

    @TestCase
    func variantsSerializeAsBaseKinds() {
        // act & assert
        @Expect("{\"kind\":\"base\",\"name\":\"string\"}", wireOf(EnumerationType.String))
        @Expect("{\"kind\":\"base\",\"name\":\"integer\"}", wireOf(EnumerationType.Integer))
        @Expect("{\"kind\":\"base\",\"name\":\"uinteger\"}", wireOf(EnumerationType.UInteger))
    }

    @TestCase[json in [ "{\"kind\":\"base\",\"name\":\"string\"}", "{\"kind\":\"base\",\"name\":\"integer\"}", 
 "{\"kind\":\"base\",\"name\":\"uinteger\"}" ]]
    func roundTrips(json: String) {
        // act & assert
        @Expect(json, wireOf(EnumerationType.deserialize(dmOf(json))))
    }

    @TestCase
    func nonBaseKindThrows() {
        // act
        let e = @AssertThrows[DataModelException](
            EnumerationType.deserialize(dmOf("{\"kind\":\"reference\",\"name\":\"string\"}")))

        // assert
        @Expect("unexpected `kind` field value", e.message)
    }

    @TestCase
    func unsupportedNameThrows() {
        // act
        let e = @AssertThrows[DataModelException](
            EnumerationType.deserialize(dmOf("{\"kind\":\"base\",\"name\":\"decimal\"}")))

        // assert
        @Expect("invalid `EnumerationType` value", e.message)
    }

    @TestCase
    func absentNameThrows() {
        // act
        let e = @AssertThrows[DataModelException](EnumerationType.deserialize(dmOf("{\"kind\":\"base\"}")))

        // assert
        @Expect("required field \"name\" is absent", e.message)
    }
}

@Test
class EnumerationTest {
    static let json = "{\"name\":\"ErrorCodes\",\"type\":{\"kind\":\"base\",\"name\":\"integer\"},\"values\":[{\"name\":\"ParseError\",\"value\":-32700,\"proposed\":false}],\"supportsCustomValues\":true,\"proposed\":false}"

    @TestCase
    func deserializesNameTypeAndValues() {
        // act
        let sut = Enumeration.deserialize(dmOf(json))

        // assert
        @Expect("ErrorCodes", sut.name)
        assertSameJson("{\"kind\":\"base\",\"name\":\"integer\"}", sut.`type`.serialize())
        @Expect(1, sut.values.size)
        @Expect("ParseError", sut.values[0].name)
        @Expect(true, sut.supportsCustomValues.getOrThrow())
    }

    @TestCase
    func absentSupportsCustomValuesStaysAbsent() {
        // arrange
        let minimal = "{\"name\":\"FileOperationPatternKind\",\"type\":{\"kind\":\"base\",\"name\":\"string\"},\"values\":[]}"

        // act
        let sut = Enumeration.deserialize(dmOf(minimal))

        // assert
        @Assert(sut.supportsCustomValues.isNone())
        @Assert(sut.proposed.isNone())
        @Expect(0, sut.values.size)
    }

    @TestCase
    func roundTrips() {
        // act & assert
        assertSameJson(json, Enumeration.deserialize(dmOf(json)).serialize())
    }

    @TestCase
    func absentValuesThrows() {
        // arrange
        let missing = "{\"name\":\"ErrorCodes\",\"type\":{\"kind\":\"base\",\"name\":\"integer\"}}"

        // act
        let e = @AssertThrows[DataModelException](Enumeration.deserialize(dmOf(missing)))

        // assert
        @Expect("required field \"values\" is absent", e.message)
    }

    @TestCase
    func absentTypeThrows() {
        // arrange
        let missing = "{\"name\":\"ErrorCodes\",\"values\":[]}"

        // act
        let e = @AssertThrows[DataModelException](Enumeration.deserialize(dmOf(missing)))

        // assert
        @Expect("required field \"type\" is absent", e.message)
    }
}

@Test
class StructureTest {
    @TestCase
    func minimalStructureHasNoExtendsOrMixins() {
        // arrange
        let json = "{\"name\":\"Position\",\"properties\":[{\"name\":\"line\",\"type\":{\"kind\":\"base\",\"name\":\"uinteger\"}}]}"

        // act
        let sut = Structure.deserialize(dmOf(json))

        // assert
        @Expect("Position", sut.name)
        @Expect(1, sut.properties.size)
        @Assert(sut.extends.isNone())
        @Assert(sut.mixins.isNone())
        @Assert(sut.proposed.isNone())
    }

    @TestCase
    func extendsAndMixinsAreDeserialized() {
        // arrange
        let json = "{\"name\":\"Diagnostic\",\"extends\":[{\"kind\":\"reference\",\"name\":\"Base\"}],\"mixins\":[{\"kind\":\"reference\",\"name\":\"WorkDoneProgressParams\"},{\"kind\":\"reference\",\"name\":\"PartialResultParams\"}],\"properties\":[]}"

        // act
        let sut = Structure.deserialize(dmOf(json))

        // assert
        @Expect(1, sut.extends.getOrThrow().size)
        @Expect(2, sut.mixins.getOrThrow().size)
    }

    @TestCase
    func roundTrips() {
        // arrange - serialize writes the required fields first, then the optionals it holds
        let json = "{\"name\":\"Position\",\"properties\":[{\"name\":\"line\",\"type\":{\"kind\":\"base\",\"name\":\"uinteger\"},\"optional\":false,\"proposed\":false}],\"proposed\":false,\"extends\":[{\"kind\":\"reference\",\"name\":\"Base\"}],\"documentation\":\"A position.\",\"since\":\"3.17.0\"}"

        // act & assert
        assertSameJson(json, Structure.deserialize(dmOf(json)).serialize())
    }

    @TestCase
    func absentPropertiesThrows() {
        // act
        let e = @AssertThrows[DataModelException](Structure.deserialize(dmOf("{\"name\":\"Position\"}")))

        // assert
        @Expect("required field \"properties\" is absent", e.message)
    }

    @TestCase
    func absentNameThrows() {
        // act
        let e = @AssertThrows[DataModelException](Structure.deserialize(dmOf("{\"properties\":[]}")))

        // assert
        @Expect("required field \"name\" is absent", e.message)
    }
}

@Test
class TypeAliasTest {
    @TestCase
    func deserializesNameAndType() {
        // arrange
        let json = "{\"name\":\"Definition\",\"type\":{\"kind\":\"or\",\"items\":[{\"kind\":\"reference\",\"name\":\"Location\"},{\"kind\":\"reference\",\"name\":\"LocationLink\"}]}}"

        // act
        let sut = TypeAlias.deserialize(dmOf(json))

        // assert
        @Expect("Definition", sut.name)
        @Assert(sut.proposed.isNone())
        @Assert(sut.documentation.isNone())
    }

    @TestCase
    func roundTrips() {
        // arrange
        let json = "{\"name\":\"DocumentSelector\",\"type\":{\"kind\":\"array\",\"element\":{\"kind\":\"reference\",\"name\":\"DocumentFilter\"}},\"proposed\":false,\"documentation\":\"A document selector.\"}"

        // act & assert
        assertSameJson(json, TypeAlias.deserialize(dmOf(json)).serialize())
    }

    @TestCase
    func absentTypeThrows() {
        // act
        let e = @AssertThrows[DataModelException](TypeAlias.deserialize(dmOf("{\"name\":\"Definition\"}")))

        // assert
        @Expect("required field \"type\" is absent", e.message)
    }
}

@Test
class RequestTest {
    static let minimalJson = "{\"method\":\"shutdown\",\"result\":{\"kind\":\"base\",\"name\":\"null\"},\"messageDirection\":\"clientToServer\"}"

    @TestCase
    func minimalRequestLeavesEveryOptionalAbsent() {
        // act
        let sut = Request.deserialize(dmOf(minimalJson))

        // assert
        @Expect("shutdown", sut.method)
        @Assert(sut.proposed.isNone())
        @Assert(sut.typeName.isNone())
        @Assert(sut.params.isNone())
        @Assert(sut.partialResult.isNone())
        @Assert(sut.errorData.isNone())
        @Assert(sut.registrationMethod.isNone())
        @Assert(sut.registrationOptions.isNone())
        @Assert(sut.documentation.isNone())
        @Assert(sut.since.isNone())
        @Assert(sut.sinceTags.isNone())
        @Assert(sut.deprecated.isNone())
        @Assert(sut.clientCapability.isNone())
        @Assert(sut.serverCapability.isNone())
    }

    @TestCase
    func minimalRequestSerializesWithoutOptionalKeys() {
        // act & assert
        assertSameJson(minimalJson, Request.deserialize(dmOf(minimalJson)).serialize())
    }

    @TestCase
    func messageDirectionIsRead() {
        // arrange
        let json = "{\"method\":\"window/showMessageRequest\",\"result\":{\"kind\":\"base\",\"name\":\"null\"},\"messageDirection\":\"serverToClient\"}"

        // act
        let sut = Request.deserialize(dmOf(json))

        // assert
        @Expect("serverToClient", sut.messageDirection.serialize().asStringOrThrow())
    }

    @TestCase
    func singleParamsTypeBecomesOne() {
        // arrange
        let json = "{\"method\":\"textDocument/hover\",\"params\":{\"kind\":\"reference\",\"name\":\"HoverParams\"},\"result\":{\"kind\":\"reference\",\"name\":\"Hover\"},\"messageDirection\":\"clientToServer\"}"

        // act
        let sut = Request.deserialize(dmOf(json))

        // assert
        let name = match (sut.params.getOrThrow()) {
            case OneOrMany<Type>.One(Type.Reference(name)) => name
            case _ => "not a single reference"
        }
        @Expect("HoverParams", name)
    }

    @TestCase
    func multipleParamsTypesBecomeMany() {
        // arrange
        let json = "{\"method\":\"custom/multi\",\"params\":[{\"kind\":\"reference\",\"name\":\"A\"},{\"kind\":\"reference\",\"name\":\"B\"}],\"result\":{\"kind\":\"base\",\"name\":\"null\"},\"messageDirection\":\"both\"}"

        // act
        let sut = Request.deserialize(dmOf(json))

        // assert
        let count = match (sut.params.getOrThrow()) {
            case OneOrMany<Type>.Many(items) => items.size
            case _ => -1
        }
        @Expect(2, count)
    }

    @TestCase
    func fullyPopulatedRequestRoundTrips() {
        // arrange - key order follows serialize(): required fields, then optionals in declaration order
        let json = "{\"method\":\"textDocument/implementation\",\"result\":{\"kind\":\"reference\",\"name\":\"Definition\"},\"messageDirection\":\"clientToServer\",\"proposed\":true,\"typeName\":\"ImplementationRequest\",\"params\":{\"kind\":\"reference\",\"name\":\"ImplementationParams\"},\"partialResult\":{\"kind\":\"array\",\"element\":{\"kind\":\"reference\",\"name\":\"Location\"}},\"errorData\":{\"kind\":\"base\",\"name\":\"string\"},\"registrationMethod\":\"textDocument/implementation\",\"registrationOptions\":{\"kind\":\"reference\",\"name\":\"ImplementationRegistrationOptions\"},\"documentation\":\"Go to implementation.\",\"since\":\"3.6.0\",\"sinceTags\":[\"proposed\"],\"deprecated\":\"use something else\",\"clientCapability\":\"textDocument.implementation\",\"serverCapability\":\"implementationProvider\"}"

        // act & assert
        assertSameJson(json, Request.deserialize(dmOf(json)).serialize())
    }

    @TestCase
    func absentResultThrows() {
        // arrange
        let json = "{\"method\":\"shutdown\",\"messageDirection\":\"clientToServer\"}"

        // act
        let e = @AssertThrows[DataModelException](Request.deserialize(dmOf(json)))

        // assert
        @Expect("required field \"result\" is absent", e.message)
    }

    @TestCase
    func absentMessageDirectionThrows() {
        // arrange
        let json = "{\"method\":\"shutdown\",\"result\":{\"kind\":\"base\",\"name\":\"null\"}}"

        // act
        let e = @AssertThrows[DataModelException](Request.deserialize(dmOf(json)))

        // assert
        @Expect("required field \"messageDirection\" is absent", e.message)
    }
}

@Test
class NotificationTest {
    static let minimalJson = "{\"method\":\"exit\",\"messageDirection\":\"clientToServer\"}"

    @TestCase
    func minimalNotificationLeavesEveryOptionalAbsent() {
        // act
        let sut = Notification.deserialize(dmOf(minimalJson))

        // assert
        @Expect("exit", sut.method)
        @Assert(sut.proposed.isNone())
        @Assert(sut.typeName.isNone())
        @Assert(sut.params.isNone())
        @Assert(sut.registrationMethod.isNone())
        @Assert(sut.registrationOptions.isNone())
        @Assert(sut.documentation.isNone())
        @Assert(sut.since.isNone())
        @Assert(sut.sinceTags.isNone())
        @Assert(sut.deprecated.isNone())
        @Assert(sut.clientCapability.isNone())
        @Assert(sut.serverCapability.isNone())
    }

    @TestCase
    func minimalNotificationSerializesWithoutOptionalKeys() {
        // act & assert
        assertSameJson(minimalJson, Notification.deserialize(dmOf(minimalJson)).serialize())
    }

    @TestCase
    func fullyPopulatedNotificationRoundTrips() {
        // arrange
        let json = "{\"method\":\"textDocument/didOpen\",\"messageDirection\":\"clientToServer\",\"proposed\":false,\"typeName\":\"DidOpenTextDocumentNotification\",\"params\":{\"kind\":\"reference\",\"name\":\"DidOpenTextDocumentParams\"},\"registrationMethod\":\"textDocument/didOpen\",\"registrationOptions\":{\"kind\":\"reference\",\"name\":\"TextDocumentRegistrationOptions\"},\"documentation\":\"The document open notification.\",\"since\":\"3.0.0\",\"sinceTags\":[\"proposed\"],\"deprecated\":\"n/a\",\"clientCapability\":\"textDocument.synchronization\",\"serverCapability\":\"textDocumentSync\"}"

        // act & assert
        assertSameJson(json, Notification.deserialize(dmOf(json)).serialize())
    }

    @TestCase
    func absentMethodThrows() {
        // act
        let e = @AssertThrows[DataModelException](
            Notification.deserialize(dmOf("{\"messageDirection\":\"clientToServer\"}")))

        // assert
        @Expect("required field \"method\" is absent", e.message)
    }
}

@Test
class MetaModelTest {
    static let json = "{\"metaData\":{\"version\":\"3.18.0\"},\"requests\":[{\"method\":\"shutdown\",\"result\":{\"kind\":\"base\",\"name\":\"null\"},\"messageDirection\":\"clientToServer\",\"proposed\":false}],\"notifications\":[{\"method\":\"exit\",\"messageDirection\":\"clientToServer\",\"proposed\":false}],\"structures\":[{\"name\":\"Position\",\"properties\":[{\"name\":\"line\",\"type\":{\"kind\":\"base\",\"name\":\"uinteger\"},\"optional\":false,\"proposed\":false}],\"proposed\":false}],\"enumerations\":[{\"name\":\"ErrorCodes\",\"type\":{\"kind\":\"base\",\"name\":\"integer\"},\"values\":[{\"name\":\"ParseError\",\"value\":-32700,\"proposed\":false}],\"supportsCustomValues\":false,\"proposed\":false}],\"typeAliases\":[{\"name\":\"Definition\",\"type\":{\"kind\":\"reference\",\"name\":\"Location\"},\"proposed\":false}]}"

    @TestCase
    func deserializesEverySection() {
        // act
        let sut = MetaModel.deserialize(dmOf(json))

        // assert
        @Expect("3.18.0", sut.metaData.version)
        @Expect(1, sut.requests.size)
        @Expect("shutdown", sut.requests[0].method)
        @Expect(1, sut.notifications.size)
        @Expect("exit", sut.notifications[0].method)
        @Expect(1, sut.structures.size)
        @Expect("Position", sut.structures[0].name)
        @Expect(1, sut.enumerations.size)
        @Expect("ErrorCodes", sut.enumerations[0].name)
        @Expect(1, sut.typeAliases.size)
        @Expect("Definition", sut.typeAliases[0].name)
    }

    @TestCase
    func roundTrips() {
        // act & assert
        assertSameJson(json, MetaModel.deserialize(dmOf(json)).serialize())
    }

    @TestCase
    func emptySectionsAreAllowed() {
        // arrange
        let empty = "{\"metaData\":{\"version\":\"3.18.0\"},\"requests\":[],\"notifications\":[],\"structures\":[],\"enumerations\":[],\"typeAliases\":[]}"

        // act
        let sut = MetaModel.deserialize(dmOf(empty))

        // assert
        @Expect(0, sut.requests.size)
        @Expect(0, sut.typeAliases.size)
    }

    @TestCase
    func absentSectionThrows() {
        // arrange - every section is required, even when it would be empty
        let missing = "{\"metaData\":{\"version\":\"3.18.0\"},\"requests\":[],\"notifications\":[],\"structures\":[],\"enumerations\":[]}"

        // act
        let e = @AssertThrows[DataModelException](MetaModel.deserialize(dmOf(missing)))

        // assert
        @Expect("required field \"typeAliases\" is absent", e.message)
    }

    @TestCase
    func nonStructThrows() {
        // act
        let e = @AssertThrows[DataModelException](MetaModel.deserialize(dmOf("[]")))

        // assert
        @Expect("expected `DataModelStruct`", e.message)
    }
}

func fieldsOf(dms: DataModelStruct): HashMap<String, DataModel> {
    let byName = HashMap<String, DataModel>()
    for (f in dms.getFields()) {
        byName[f.getName()] = f.getData()
    }

    byName
}

/**
 * The path of the first structural difference, or `None` when the two documents are
 * equal by JSON rules: object members as an unordered name -> value mapping, arrays in
 * order. `serialize()` writes required fields before optional ones, so comparing the
 * rendered strings would fail on a key reordering that means nothing.
 */
func firstDifference(expected: DataModel, actual: DataModel, path!: String = "$"): ?String {
    match ((expected, actual)) {
        case (e: DataModelStruct, a: DataModelStruct) =>
            let expectedFields = fieldsOf(e)
            let actualFields = fieldsOf(a)
            for ((name, expectedValue) in expectedFields) {
                match (actualFields.get(name)) {
                    case None => return "${path}.${name} (dropped on the way out)"
                    case Some(actualValue) =>
                        if (let Some(diff) <- firstDifference(expectedValue, actualValue, path: "${path}.${name}")) {
                            return diff
                        }
                }
            }
            for ((name, _) in actualFields) {
                if (expectedFields.get(name).isNone()) {
                    return "${path}.${name} (invented on the way out)"
                }
            }
            None
        case (e: DataModelSeq, a: DataModelSeq) =>
            let expectedItems = e.getItems()
            let actualItems = a.getItems()
            if (expectedItems.size != actualItems.size) {
                return "${path} (${expectedItems.size} items in, ${actualItems.size} out)"
            }
            for (i in 0..expectedItems.size) {
                if (let Some(diff) <- firstDifference(expectedItems[i], actualItems[i], path: "${path}[${i}]")) {
                    return diff
                }
            }
            None
        case (e: DataModelString, a: DataModelString) where e.getValue() == a.getValue() => None
        case (e: DataModelInt, a: DataModelInt) where e.getValue() == a.getValue() => None
        case (e: DataModelFloat, a: DataModelFloat) where e.getValue() == a.getValue() => None
        case (e: DataModelBool, a: DataModelBool) where e.getValue() == a.getValue() => None
        case (_: DataModelNull, _: DataModelNull) => None
        case _ => "${path} (value differs)"
    }
}

func assertSameJson(expected: String, actual: DataModel): Unit {
    @Expect("none", firstDifference(dmOf(expected), actual) ?? "none")
}

/**
 * The end-to-end check: the real 3.18 meta model - the only input this generator has to read.
 */
@Test
class ShippedMetaModelTest {
    static let SHIPPED_META_MODEL = "modules/lsp_codegen/metaModel.json"

    static func read(): DataModel {
        dmOf(String.fromUtf8(File.readFrom(SHIPPED_META_MODEL)))
    }

    @TestCase
    func deserializesEveryDeclarationInTheShippedMetaModel() {
        // arrange
        let dm = read()

        // act
        let sut = MetaModel.deserialize(dm)

        // assert - the counts are just a floor; the point is that nothing in the file throws
        @Expect("3.18.0", sut.metaData.version)
        @Expect(sut.requests.size > 50)
        @Expect(sut.notifications.size > 20)
        @Expect(sut.structures.size > 100)
        @Expect(sut.enumerations.size > 20)
        @Expect(sut.typeAliases.size > 10)
    }

    @TestCase
    func theShippedMetaModelIsReadAndWrittenLosslessly() {
        // arrange
        let source = read()

        // act
        let rewritten = MetaModel.deserialize(source).serialize()

        // assert
        @Expect(firstDifference(source, rewritten), None)
    }
}
