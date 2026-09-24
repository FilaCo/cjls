package lsp_codegen

import std.ast.*
import std.collection.{ArrayList, enumerate}

/**
 * A metaModel structure - or literal - declared as a struct whose primary constructor parameters are
 * its fields on the wire.
 */
struct StructIr {
    StructIr(let doc: DocIr, let ident!: String, let fields!: Array<FieldIr>, let tag!: ?SerializableTag = None) {}
}

struct FieldIr {
    FieldIr(
        let doc: DocIr,
        // unescaped: the wire name as well, the derive strips the backquotes the emitter adds
        let ident!: String,
        let fieldType!: TypeIr,
        let isOptional!: Bool,
        let qualifiesNone!: Bool = false
    ) {}
}

func resolveStruct(cfg: Config, resolver: TypeResolver, structure: Structure): ?StructIr {
    let ident = match (cfg.typeMap.bind(structure.name)) {
        case Owned(ident) => ident
        case _ => return None
    }

    resolveFields(resolveDoc(structure), ident, resolver.flattenedProperties(structure), resolver)
}

func resolveLiteral(resolver: TypeResolver, literal: LiteralIr): StructIr {
    let properties = literal.literal.properties.map {
        it: Property => DeclaredProperty(declaredBy: literal.ident, property: it)
    }

    resolveFields(resolveDoc(literal.literal), literal.ident, properties, resolver)
}

/**
 * A string literal property is the tag of the struct rather than a field of it: LSP marks
 * `CreateFile` with `kind: 'create'`, and a value that can only ever be one string is no field to set.
 */
private func resolveFields(doc: DocIr, ident: String, properties: Array<DeclaredProperty>, resolver: TypeResolver): StructIr {
    let fields = ArrayList<FieldIr>()
    var tag: ?SerializableTag = None
    for (declared in properties) {
        let property = declared.property
        if (let StringLiteral(value) <- property.propertyType) {
            if (tag.isSome()) {
                throw IllegalStateException("`${ident}` has more than one string literal property")
            }
            if (property.optional ?? false) {
                throw IllegalStateException("`${ident}.${property.name}` is an optional string literal, which is no tag")
            }
            tag = SerializableTag(field: property.name, value: value)
            continue
        }

        let fieldType = resolver.resolve(property.propertyType, context: declared.declaredBy + property.name.toAsciiPascalCase())
        fields.add(
            FieldIr(
                resolveDoc(property),
                ident: property.name,
                fieldType: fieldType,
                isOptional: property.optional ?? false,
                qualifiesNone: resolver.hasOwnNone(fieldType)
            )
        )
    }

    StructIr(doc, ident: ident, fields: fields.toArray(), tag: tag)
}

extend CjEmitter {
    /**
     * Every parameter is named: `ClientCapabilities`-sized structs are unusable positionally, and a
     * property a newer metaModel inserts cannot silently shift anybody's arguments.
     */
    func emitStruct(structIr: StructIr): Unit {
        let structIdent = escapedIdent(structIr.ident)

        emitDoc(structIr.doc)
        // absent and `None` are different messages in LSP - an optional field is left out, never `null`
        emitDerives([Serializable(SerializableTypeOptions(skipNone: true, tag: structIr.tag))])
        emit(quote(public struct $structIdent))
        blockln {
            =>
                if (structIr.fields.isEmpty()) {
                    emitln(quote(public $structIdent() {}))
                    return
                }

                emitln(quote(public $structIdent) + Tokens(Token(LPAREN)))
                indented {
                    => for ((i, field) in structIr.fields |> enumerate) {
                        if (i > 0) {
                            nl()
                        }
                        emitField(field, isLast: i == structIr.fields.size - 1)
                    }
                }
                emitln(Tokens(Token(RPAREN), Token(LCURL), Token(RCURL)))
        }
    }

    private func emitField(field: FieldIr, isLast!: Bool): Unit {
        let fieldIdent = escapedIdent(field.ident)
        let fieldType = field.fieldType
        var declaration = if (field.isOptional && field.qualifiesNone) {
            quote(public let $fieldIdent!: ?$fieldType = Option<$fieldType>.None)
        } else if (field.isOptional) {
            quote(public let $fieldIdent!: ?$fieldType = None)
        } else {
            quote(public let $fieldIdent!: $fieldType)
        }
        if (!isLast) {
            declaration += Tokens(Token(COMMA))
        }

        emitDoc(field.doc)
        emitln(declaration)
    }
}
