package cjls.handlers

import std.env.getTempDirectory
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.NoopLogger
import rope.{Encoding, Rope}
import loupe.vfs.VfsPath
import cjls.lsp_types.*
import cjls.lsp_types.Range as LspRange
import cjls.server.*

let URI = "file:///nowhere/a.cj"

func opened(text: String, uri!: String = URI): ServerState {
    let state = ServerState()
    handleDidOpen(state, DidOpenTextDocumentParams(
        textDocument: TextDocumentItem(uri: uri, languageId: LanguageKind("cangjie"), version: 1, text: text)))
    state
}

func partial(startLine: UInt32, startColumn: UInt32, endLine: UInt32, endColumn: UInt32, text: String): TextDocumentContentChangeEvent {
    TextDocumentContentChangeEvent.AsTextDocumentContentChangePartial(TextDocumentContentChangePartial(
        range: LspRange(start: Position(line: startLine, character: startColumn), end: Position(line: endLine, character: endColumn)),
        text: text))
}

func change(state: ServerState, changes: Array<TextDocumentContentChangeEvent>): Unit {
    handleDidChange(state, NoopLogger(), DidChangeTextDocumentParams(
        textDocument: VersionedTextDocumentIdentifier(uri: URI, version: 2), contentChanges: changes))
}

func textOf(state: ServerState): ?String {
    state.fileContents(VfsPath.fromUri(URI))?.toString()
}

@Test
class DocumentSyncTest {
    @TestCase
    func anOpenedDocumentIsWhatTheAnalysisSees() {
        // act
        let state = opened("func f() {}\n")

        // assert
        let snapshot = state.snapshot()
        let file = snapshot.sourceFile(VfsPath.fromUri(URI)).getOrThrow()
        @Expect(file.text(snapshot.analysis).toString(), "func f() {}\n")
    }

    @TestCase
    func changesApplyInOrderEachToWhatTheOneBeforeLeft() {
        // arrange
        let state = opened("let a = 1\nlet b = 2\n")

        // act
        change(state, [partial(0, 4, 0, 5, "x"), partial(1, 0, 1, 0, "// b\n"), partial(2, 8, 2, 9, "3")])

        // assert
        @Expect(textOf(state), Some("let x = 1\n// b\nlet b = 3\n"))
        @Expect(state.openDocuments.get(VfsPath.fromUri(URI)), Some(Int32(2)))
    }

    @TestCase
    func aWholeDocumentChangeReplacesTheText() {
        // arrange
        let state = opened("old")

        // act
        change(state, [TextDocumentContentChangeEvent.AsTextDocumentContentChangeWholeDocument(
            TextDocumentContentChangeWholeDocument(text: "new")), partial(0, 3, 0, 3, "er")])

        // assert
        @Expect(textOf(state), Some("newer"))
    }

    @TestCase
    func columnsCountTheEncodingAgreedOn() {
        // arrange - "😀" is two UTF-16 units and four bytes
        let utf16 = opened("😀a\n")
        let utf8 = opened("😀a\n")
        utf8.encoding = Encoding.Utf8

        // act
        change(utf16, [partial(0, 2, 0, 3, "b")])
        change(utf8, [partial(0, 4, 0, 5, "b")])

        // assert
        @Expect(textOf(utf16), Some("😀b\n"))
        @Expect(textOf(utf8), Some("😀b\n"))
    }

    @TestCase
    func aBatchWithABackwardRangeIsDroppedWhole() {
        // arrange
        let state = opened("abc")

        // act
        change(state, [partial(0, 0, 0, 1, "x"), partial(0, 2, 0, 1, "y")])

        // assert
        @Expect(textOf(state), Some("abc"))
        @Expect(state.openDocuments.get(VfsPath.fromUri(URI)), Some(Int32(1)))
    }

    @TestCase
    func aChangeToADocumentNotOpenIsIgnored() {
        // arrange
        let state = ServerState()

        // act
        change(state, [partial(0, 0, 0, 0, "x")])

        // assert
        @Expect(textOf(state), None<String>)
    }

    @TestCase
    func aClosedDocumentNotOnDiskIsGone() {
        // arrange
        let state = opened("let a = 1\n")
        let file = state.snapshot().sourceFile(VfsPath.fromUri(URI)).getOrThrow()

        // act
        handleDidClose(state, DidCloseTextDocumentParams(textDocument: TextDocumentIdentifier(uri: URI)))

        // assert
        @Expect(textOf(state), None<String>)
        @Expect(state.openDocuments.isEmpty())
        @Expect(file.text(state.analysis).toString(), "")
    }

    @TestCase
    func aClosedDocumentOnDiskIsWhatTheDiskHolds() {
        // arrange
        let dir = Directory.createTemp(getTempDirectory())
        let onDisk = dir.join("b.cj")
        File.writeTo(onDisk, "on disk".toArray())
        let uri = VfsPath.file(onDisk.toString()).toUri()
        let state = opened("in the editor", uri: uri)

        // act
        handleDidClose(state, DidCloseTextDocumentParams(textDocument: TextDocumentIdentifier(uri: uri)))
        remove(dir, recursive: true)

        // assert
        @Expect(state.fileContents(VfsPath.fromUri(uri))?.toString(), Some("on disk"))
    }
}
