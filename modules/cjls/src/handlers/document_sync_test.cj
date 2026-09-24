package cjls.handlers

import std.env.getTempDirectory
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.NoopLogger
import stdxx.Nullable
import rope.{Encoding, Rope}
import loupe.vfs.VfsPath
import cjls.lsp_types.*
import cjls.lsp_types.Range as LspRange
import cjls.server.*

let URI = "file:///nowhere/a.cj"

func opened(text: String): Database {
    let db = Database()
    handleDidOpen(db, DidOpenTextDocumentParams(
        textDocument: TextDocumentItem(uri: URI, languageId: LanguageKind("cangjie"), version: 1, text: text)))
    db
}

func partial(startLine: UInt32, startColumn: UInt32, endLine: UInt32, endColumn: UInt32, text: String): TextDocumentContentChangeEvent {
    TextDocumentContentChangeEvent.AsTextDocumentContentChangePartial(TextDocumentContentChangePartial(
        range: LspRange(start: Position(line: startLine, character: startColumn), end: Position(line: endLine, character: endColumn)),
        text: text))
}

func change(db: Database, changes: Array<TextDocumentContentChangeEvent>): Unit {
    handleDidChange(db, NoopLogger(), DidChangeTextDocumentParams(
        textDocument: VersionedTextDocumentIdentifier(uri: URI, version: 2), contentChanges: changes))
}

func textOf(db: Database): ?String {
    db.fileContents(VfsPath.fromUri(URI))?.toString()
}

@Test
class DocumentSyncTest {
    @TestCase
    func anOpenedDocumentIsWhatTheAnalysisSees() {
        // act
        let db = opened("func f() {}\n")

        // assert
        let snapshot = db.snapshot()
        let file = snapshot.sourceFile(VfsPath.fromUri(URI)).getOrThrow()
        @Expect(file.text(snapshot.analysis).toString(), "func f() {}\n")
    }

    @TestCase
    func changesApplyInOrderEachToWhatTheOneBeforeLeft() {
        // arrange
        let db = opened("let a = 1\nlet b = 2\n")

        // act
        change(db, [partial(0, 4, 0, 5, "x"), partial(1, 0, 1, 0, "// b\n"), partial(2, 8, 2, 9, "3")])

        // assert
        @Expect(textOf(db), Some("let x = 1\n// b\nlet b = 3\n"))
        @Expect(db.openDocuments.get(VfsPath.fromUri(URI)), Some(Int32(2)))
    }

    @TestCase
    func aWholeDocumentChangeReplacesTheText() {
        // arrange
        let db = opened("old")

        // act
        change(db, [TextDocumentContentChangeEvent.AsTextDocumentContentChangeWholeDocument(
            TextDocumentContentChangeWholeDocument(text: "new")), partial(0, 3, 0, 3, "er")])

        // assert
        @Expect(textOf(db), Some("newer"))
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
        let db = opened("abc")

        // act
        change(db, [partial(0, 0, 0, 1, "x"), partial(0, 2, 0, 1, "y")])

        // assert
        @Expect(textOf(db), Some("abc"))
        @Expect(db.openDocuments.get(VfsPath.fromUri(URI)), Some(Int32(1)))
    }

    @TestCase
    func aChangeToADocumentNotOpenIsIgnored() {
        // arrange
        let db = Database()

        // act
        change(db, [partial(0, 0, 0, 0, "x")])

        // assert
        @Expect(textOf(db), None<String>)
    }

    @TestCase
    func aClosedDocumentNotOnDiskIsGone() {
        // arrange
        let db = opened("let a = 1\n")
        let file = db.snapshot().sourceFile(VfsPath.fromUri(URI)).getOrThrow()

        // act
        handleDidClose(db, DidCloseTextDocumentParams(textDocument: TextDocumentIdentifier(uri: URI)))

        // assert
        @Expect(textOf(db), None<String>)
        @Expect(db.openDocuments.isEmpty())
        @Expect(file.text(db.analysis).toString(), "")
    }

    @TestCase
    func aClosedDocumentOnDiskIsWhatTheDiskHolds() {
        // arrange
        let dir = Directory.createTemp(getTempDirectory())
        let onDisk = dir.join("b.cj")
        File.writeTo(onDisk, "on disk".toArray())
        let uri = VfsPath.file(onDisk.toString()).toUri()
        let db = Database()
        handleDidOpen(db, DidOpenTextDocumentParams(
            textDocument: TextDocumentItem(uri: uri, languageId: LanguageKind("cangjie"), version: 1, text: "in the editor")))

        // act
        handleDidClose(db, DidCloseTextDocumentParams(textDocument: TextDocumentIdentifier(uri: uri)))
        remove(dir, recursive: true)

        // assert
        @Expect(db.fileContents(VfsPath.fromUri(uri))?.toString(), Some("on disk"))
    }
}

@Test
class InitializeTest {
    @TestCase
    func utf8IsAgreedOnWhenTheClientOffersIt() {
        // arrange
        let db = Database()
        let params = InitializeParams(processId: Nullable.Null, rootUri: Nullable.Null, capabilities: ClientCapabilities(
            general: GeneralClientCapabilities(positionEncodings: [PositionEncodingKind.UTF16, PositionEncodingKind.UTF8])))

        // act
        let result = handleInitialize(db, params)

        // assert
        @Expect(db.encoding, Encoding.Utf8)
        @Expect(result.capabilities.positionEncoding?.value, Some("utf-8"))
    }

    @TestCase
    func utf16IsTheDefault() {
        // arrange
        let db = Database()

        // act
        let result = handleInitialize(db, InitializeParams(processId: Nullable.Null, rootUri: Nullable.Null,
            capabilities: ClientCapabilities()))

        // assert
        @Expect(db.encoding, Encoding.Utf16)
        @Expect(result.capabilities.positionEncoding?.value, Some("utf-16"))
    }
}
