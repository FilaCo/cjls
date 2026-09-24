package lsp_codegen

import std.collection.HashMap
import std.fs.Path
import std.unittest.*
import std.unittest.testmacro.*
import stdxx.*

private func metaModelOf(
    structures!: Array<Structure> = [],
    typeAliases!: Array<TypeAlias> = [],
    enumerations!: Array<Enumeration> = []
): MetaModel {
    MetaModel(metaData: MetaData(version: "3.18.0"), requests: [], notifications: [], structures: structures,
        enumerations: enumerations, typeAliases: typeAliases)
}

private func configOf(typeMap!: TypeMap = TypeMap()): Config {
    Config(srcDir: Path("src"), outputPackage: "demo.lsp_types", typeMap: typeMap)
}

private func resolverOf(mm: MetaModel, typeMap!: TypeMap = TypeMap()): TypeResolver {
    TypeResolver(mm, configOf(typeMap: typeMap))
}

private func ref(name: String): Type {
    Type.Reference(name)
}

private func base(name: BaseTypes): Type {
    Type.Base(name)
}

private func property(name: String, t: Type, optional!: Bool = false): Property {
    Property(name: name, propertyType: t, optional: optional)
}

private func structureOf(name: String, properties: Array<Property>, extends!: Array<Type> = [],
    mixins!: Array<Type> = []): Structure {
    Structure(name: name, properties: properties, extends: extends, mixins: mixins)
}

private func variantIdents(unionIr: UnionIr): String {
    String.join(unionIr.variants.map {it: UnionVariantIr => it.ident}, delimiter: ",")
}

@Test
class ResolveUnionTest {
    @TestCase
    func aUnionIsNamedAfterItsMembersInTheOrderTheyAreMet() {
        // arrange
        let sut = resolverOf(metaModelOf())

        // act
        let t = sut.resolve(Type.Or([base(BaseTypes.String), ref("MarkupContent")]), context: "Hover")

        // assert
        @Expect("StringOrMarkupContent", t.toString())
        @Expect("AsString,AsMarkupContent", variantIdents(sut.unions[0]))
    }

    @TestCase
    func theSameMembersInAnotherOrderAreTheSameUnion() {
        // arrange
        let sut = resolverOf(metaModelOf())

        // act
        let first = sut.resolve(Type.Or([base(BaseTypes.String), ref("MarkupContent")]), context: "A")
        let second = sut.resolve(Type.Or([ref("MarkupContent"), base(BaseTypes.String)]), context: "B")

        // assert
        @Expect(first.toString(), second.toString())
        @Expect(1, sut.unions.size)
    }

    @TestCase
    func anArrayMemberIsNamedInThePlural() {
        // arrange
        let sut = resolverOf(metaModelOf())

        // act
        let t = sut.resolve(Type.Or([ref("Location"), Type.Array(ref("Location"))]), context: "Result")

        // assert
        @Expect("LocationOrLocations", t.toString())
        @Expect("Array<Location>", sut.unions[0].variants[1].payloads[0].toString())
    }

    @TestCase
    func theFirstAliasDefiningAUnionNamesItAndLaterOnesAliasThatName() {
        // arrange
        let locations = Type.Or([ref("Location"), Type.Array(ref("Location"))])
        let sut = resolverOf(metaModelOf(typeAliases: [
            TypeAlias(name: "Definition", typeAliasType: locations),
            TypeAlias(name: "Declaration", typeAliasType: locations)
        ]))

        // act
        let definition = sut.resolve(locations, context: "Definition")

        // assert
        @Expect("Definition", definition.toString())
        @Expect("Definition", sut.unions[0].ident)
    }

    @TestCase
    func nullOutsideTheMembersMakesTheUnionNullable() {
        // arrange
        let sut = resolverOf(metaModelOf())

        // act
        let t = sut.resolve(Type.Or([ref("Location"), Type.Array(ref("Location")), base(BaseTypes.Null)]),
            context: "Result")

        // assert
        @Expect("Nullable<LocationOrLocations>", t.toString())
    }

    @TestCase
    func aTypeWithNullAmongItsOwnValuesIsNotWrappedAgain() {
        // arrange
        let anyValue = TypeAlias(name: "LSPAny", typeAliasType: Type.Or([base(BaseTypes.String), base(BaseTypes.Null)]))
        let sut = resolverOf(metaModelOf(typeAliases: [anyValue]))

        // act
        let t = sut.resolve(Type.Or([ref("LSPAny"), base(BaseTypes.Null)]), context: "Data")

        // assert
        @Expect("LSPAny", t.toString())
    }

    @TestCase
    func theMemberRequiringMoreKeysIsTriedFirst() {
        // arrange
        let codeAction = structureOf("CodeAction", [property("title", base(BaseTypes.String)),
            property("command", ref("Command"), optional: true)])
        let command = structureOf("Command", [property("title", base(BaseTypes.String)),
            property("command", base(BaseTypes.String))])
        let sut = resolverOf(metaModelOf(structures: [codeAction, command]))

        // act
        sut.resolve(Type.Or([ref("CodeAction"), ref("Command")]), context: "Result")

        // assert
        @Expect("AsCommand,AsCodeAction", variantIdents(sut.unions[0]))
    }

    @TestCase
    func aPairMemberHasOnePayloadPerItem() {
        // arrange
        let sut = resolverOf(metaModelOf())
        let pair = Type.Tuple([base(BaseTypes.UInteger), base(BaseTypes.UInteger)])

        // act
        let t = sut.resolve(Type.Or([base(BaseTypes.String), pair]), context: "Label")

        // assert
        @Expect("StringOrUIntegerPair", t.toString())
        @Expect(2, sut.unions[0].variants[1].payloads.size)
    }

    @TestCase
    func aConfigAliasedUnionIsReferredToButNotDeclared() {
        // arrange
        let token = Type.Or([base(BaseTypes.Integer), base(BaseTypes.String)])
        let typeMap = TypeMap(entries: HashMap([("ProgressToken", TypeBinding.Aliased("IntegerOrString"))]))
        let sut = resolverOf(metaModelOf(typeAliases: [TypeAlias(name: "ProgressToken", typeAliasType: token)]),
            typeMap: typeMap)

        // act
        let t = sut.resolve(token, context: "Token")

        // assert
        @Expect("ProgressToken", t.toString())
        @Expect(sut.unions.isEmpty())
    }

    @TestCase
    func aUnionOfTwoLiteralsIsRefusedRatherThanMergedIntoOne() {
        // arrange
        let first = Type.Literal(StructureLiteral(properties: [property("text", base(BaseTypes.String))]))
        let second = Type.Literal(StructureLiteral(properties: [property("uri", base(BaseTypes.String))]))
        let sut = resolverOf(metaModelOf())

        // act & assert
        @AssertThrows[IllegalStateException](sut.resolve(Type.Or([first, second]), context: "ChangeEvent"))
    }

    @TestCase
    func anAliasOfAUnionHoldingALiteralIsRefusedRatherThanClashingWithIt() {
        // arrange
        let union = Type.Or([base(BaseTypes.Boolean), Type.Literal(StructureLiteral(properties: []))])
        let alias = TypeAlias(name: "RangeOption", typeAliasType: union)
        let sut = resolverOf(metaModelOf(typeAliases: [alias]))

        // act & assert
        @AssertThrows[IllegalStateException](sut.resolve(union, context: "RangeOption"))
    }
}

@Test
class ResolveStructTest {
    @TestCase
    func inheritedPropertiesComeFirstAndARedeclaredOneIsReplacedInPlace() {
        // arrange
        let resourceOperation = structureOf("ResourceOperation", [property("kind", base(BaseTypes.String)),
            property("annotationId", base(BaseTypes.String), optional: true)])
        let deleteFile = structureOf("DeleteFile", [property("kind", Type.StringLiteral("delete")),
            property("uri", base(BaseTypes.DocumentUri))], extends: [ref("ResourceOperation")])
        let mm = metaModelOf(structures: [resourceOperation, deleteFile])

        // act
        let properties = resolverOf(mm).flattenedProperties(deleteFile)

        // assert
        @Expect("kind,annotationId,uri", String.join(properties.map {it: DeclaredProperty => it.property.name}, delimiter: ","))
    }

    @TestCase
    func aStringLiteralPropertyIsTheTagInsteadOfAField() {
        // arrange
        let deleteFile = structureOf("DeleteFile", [property("kind", Type.StringLiteral("delete")),
            property("uri", base(BaseTypes.String))])
        let mm = metaModelOf(structures: [deleteFile])
        let cfg = configOf()

        // act
        let ir = resolveStruct(cfg, TypeResolver(mm, cfg), deleteFile).getOrThrow()

        // assert
        @Expect("kind", ir.tag.getOrThrow().field)
        @Expect("delete", ir.tag.getOrThrow().value)
        @Expect(1, ir.fields.size)
    }

    @TestCase
    func aLiteralIsDeclaredUnderTheNameOfWhereItAppears() {
        // arrange
        let options = structureOf("SemanticTokensOptions",
            [property("range", Type.Or([base(BaseTypes.Boolean), Type.Literal(StructureLiteral(properties: []))]),
                optional: true)])
        let mm = metaModelOf(structures: [options])
        let cfg = configOf()
        let resolver = TypeResolver(mm, cfg)

        // act
        let ir = resolveStruct(cfg, resolver, options).getOrThrow()

        // assert
        @Expect("BooleanOrSemanticTokensOptionsRange", ir.fields[0].fieldType.toString())
        @Expect("SemanticTokensOptionsRange", resolver.literals[0].ident)
    }

    @TestCase
    func anInheritedLiteralKeepsTheNameOfWhereItIsDeclared() {
        // arrange
        let rangeType = Type.Or([base(BaseTypes.Boolean), Type.Literal(StructureLiteral(properties: []))])
        let options = structureOf("SemanticTokensOptions", [property("range", rangeType, optional: true)])
        let registrationOptions = structureOf("SemanticTokensRegistrationOptions", [],
            extends: [ref("SemanticTokensOptions")])
        let mm = metaModelOf(structures: [options, registrationOptions])
        let cfg = configOf()
        let resolver = TypeResolver(mm, cfg)

        // act
        let declared = resolveStruct(cfg, resolver, options).getOrThrow()
        let inherited = resolveStruct(cfg, resolver, registrationOptions).getOrThrow()

        // assert
        @Expect(declared.fields[0].fieldType.toString(), inherited.fields[0].fieldType.toString())
        @Expect(1, resolver.literals.size)
        @Expect(1, resolver.unions.size)
    }
}

@Test
class EmitStructTest {
    @TestCase
    func anOptionalOfAnEnumWithItsOwnNoneSpellsOutWhichNone() {
        // arrange
        let syncKind = Enumeration(name: "TextDocumentSyncKind",
            enumerationType: EnumerationType(name: EnumerationBaseType.UInteger),
            values: [EnumerationEntry(name: "None", value: IntegerOrString.Integer(0))])
        let options = structureOf("TextDocumentSyncOptions", [property("change", ref("TextDocumentSyncKind"), optional: true)])
        let mm = metaModelOf(structures: [options], enumerations: [syncKind])
        let cfg = configOf()
        let ir = resolveStruct(cfg, TypeResolver(mm, cfg), options).getOrThrow()

        // act
        let actual = emittedBy {emitter => emitter.emitStruct(ir)}

        // assert
        @Expect(actual.replace(" ", "").contains("=Option<TextDocumentSyncKind>.None"))
    }
}
