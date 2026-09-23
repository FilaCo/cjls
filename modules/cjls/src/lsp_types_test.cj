package cjls

import stdx.encoding.json.*
import stdx.serialization.serialization.*
import stdxx.*
import cjls.lsp_types.*

private func dataOf(json: String): DataModel {
    DataModel.fromJson(JsonValue.fromStr(json))
}

/**
 * What the generated `lsp_types` make of messages as editors actually send them.
 */
@Test
class LspTypesTest {
    @TestCase
    func aRealInitializeRequestReads() {
        // arrange
        let json = ##"{
            "processId": 4242,
            "clientInfo": {"name": "Visual Studio Code", "version": "1.93.0"},
            "rootPath": null,
            "rootUri": "file:///home/user/project",
            "capabilities": {
                "textDocument": {
                    "hover": {"dynamicRegistration": true, "contentFormat": ["markdown", "plaintext"]},
                    "synchronization": {"didSave": true}
                },
                "general": {"positionEncodings": ["utf-16"]}
            },
            "trace": "off",
            "workspaceFolders": [{"uri": "file:///home/user/project", "name": "project"}]
        }"##

        // act
        let params = InitializeParams.deserialize(dataOf(json))

        // assert
        @Expect(4242, params.processId.getOrThrow())
        @Expect("file:///home/user/project", params.rootUri.getOrThrow())
        @Expect(params.rootPath.getOrThrow().isNull())
        @Expect("project", params.workspaceFolders.getOrThrow().getOrThrow()[0].name)
        let hover = params.capabilities.textDocument.getOrThrow().hover.getOrThrow()
        @Expect(hover.dynamicRegistration.getOrThrow())
    }

    @TestCase
    func anAbsentOptionalIsLeftOutRatherThanWrittenAsNull() {
        // arrange
        let hover = Hover(contents: MarkupContentOrMarkedStringOrMarkedStrings.AsMarkupContent(
            MarkupContent(kind: MarkupKind.Markdown, value: "**x**")))

        // act
        let dms = hover.serialize().asStructOrThrow()

        // assert
        @Expect(dms.getOrNone("range").isNone())
        @Expect("markdown", dms.getOrThrow("contents").asStructOrThrow().getOrThrow("kind").asStringOrThrow())
    }

    @TestCase
    func aUnionTriesTheMemberRequiringMoreKeysFirst() {
        // arrange
        let command = dataOf(##"{"title": "Run", "command": "run"}"##)
        let codeAction = dataOf(##"{"title": "Fix", "command": {"title": "Run", "command": "run"}}"##)

        // act & assert
        @Expect(match (CommandOrCodeAction.deserialize(command)) {
            case AsCommand(c) => c.command == "run"
            case _ => false
        })
        @Expect(match (CommandOrCodeAction.deserialize(codeAction)) {
            case AsCodeAction(a) => a.title == "Fix"
            case _ => false
        })
    }

    @TestCase
    func theKindTagPicksTheFileOperation() {
        // arrange
        let delete = dataOf(##"{"kind": "delete", "uri": "file:///a"}"##)

        // act
        let change = TextDocumentEditOrCreateFileOrRenameFileOrDeleteFile.deserialize(delete)

        // assert
        @Expect(match (change) {
            case AsDeleteFile(d) => d.uri == "file:///a"
            case _ => false
        })
        @Expect("delete", change.serialize().asStructOrThrow().getOrThrow("kind").asStringOrThrow())
    }

    @TestCase
    func aParameterLabelIsEitherAStringOrAnOffsetPair() {
        // arrange
        let byOffsets = dataOf(##"{"label": [4, 9]}"##)

        // act
        let info = ParameterInformation.deserialize(byOffsets)

        // assert
        @Expect(match (info.label) {
            case AsUIntegerPair(start, end) => start == 4 && end == 9
            case _ => false
        })
        @Expect(match (ParameterInformation.deserialize(dataOf(##"{"label": "x"}"##)).label) {
            case AsString(s) => s == "x"
            case _ => false
        })
    }

    @TestCase
    func anEnumValueNewerThanTheMetaModelSurvives() {
        // arrange
        let json = ##"{"range": {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 1}},
            "message": "m", "severity": 1, "tags": [1, 99]}"##

        // act
        let diagnostic = Diagnostic.deserialize(dataOf(json))

        // assert
        @Expect(match (diagnostic.tags.getOrThrow()[1]) {
            case Unknown(99) => true
            case _ => false
        })
    }
}
