package lsp_codegen

import std.collection.HashMap
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import stdx.encoding.json.*
import stdx.serialization.serialization.*
import stdxx.*

private func dmOf(json: String): DataModel {
    DataModel.fromJson(JsonValue.fromStr(json))
}

private func fieldsOf(dms: DataModelStruct): HashMap<String, DataModel> {
    let byName = HashMap<String, DataModel>()
    for (f in dms.getFields()) {
        byName[f.getName()] = f.getData()
    }

    byName
}

/**
 * The path of the first difference, or `None` when the two are equal by JSON rules - object
 * members unordered, arrays in order. `serialize()` writes required fields first, so comparing the
 * rendered strings would fail on a key order that means nothing.
 */
private func firstDifference(expected: DataModel, actual: DataModel, path!: String = "$"): ?String {
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

/**
 * The declarations are plain `@DeriveExt[Serializable]`, whose behaviour `stdxx` tests; what is
 * checked here is that they match the document: the real one read and written back loses nothing,
 * and the shapes it happens not to use read too.
 */
@Test
class MetaModelTest {
    @TestCase
    func theShippedMetaModelIsReadAndWrittenLosslessly() {
        // arrange
        let source = dmOf(String.fromUtf8(File.readFrom("modules/lsp_codegen/metaModel.json")))

        // act
        let rewritten = MetaModel.deserialize(source).serialize()

        // assert
        @Expect("none", firstDifference(source, rewritten) ?? "none")
    }

    @TestCase[json in [
        ##"{"kind": "and", "items": [{"kind": "reference", "name": "A"}, {"kind": "reference", "name": "B"}]}"##,
        ##"{"kind": "integerLiteral", "value": -7}"##,
        ##"{"kind": "booleanLiteral", "value": true}"##,
        ##"{"kind": "base", "name": "RegExp"}"##,
        ##"{"kind": "map", "key": {"kind": "base", "name": "URI"}, "value": {"kind": "base", "name": "string"}}"##,
        ##"{"kind": "map", "key": {"kind": "base", "name": "integer"}, "value": {"kind": "base", "name": "string"}}"##
    ]]
    func aTypeTheShippedMetaModelDoesNotUseRoundTrips(json: String) {
        // act
        let rewritten = Type.deserialize(dmOf(json)).serialize()

        // assert
        @Expect("none", firstDifference(dmOf(json), rewritten) ?? "none")
    }

    @TestCase
    func aRequestWithPositionalParamsAndProposedTagsRoundTrips() {
        // arrange
        let json = ##"{"method": "custom/multi", "messageDirection": "both", "result": {"kind": "base", "name": "null"},
            "params": [{"kind": "reference", "name": "A"}, {"kind": "reference", "name": "B"}],
            "proposed": true, "sinceTags": ["3.18.0"], "deprecated": "use something else"}"##

        // act
        let rewritten = Request.deserialize(dmOf(json)).serialize()

        // assert
        @Expect("none", firstDifference(dmOf(json), rewritten) ?? "none")
    }
}
