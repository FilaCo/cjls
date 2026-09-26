package cjls.server

import std.collection.concurrent.LinkedBlockingQueue
import std.env.getTempDirectory
import std.sync.AtomicBool
import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.NoopLogger
import stdx.serialization.serialization.*
import stdxx.serialization.*
import jsonrpc.*
import rope.Rope
import loupe.vfs.VfsPath
import cjls.lsp_types.*
import cjls.lsp_types.Range as LspRange

let PUSHED_PATH = VfsPath.file(getTempDirectory().join("pushed.cj"))

/**
 * One diagnostic, its message the document's text as the snapshot has it.
 */
func textAsDiagnostic(snap: ServerSnapshot, path: VfsPath): Array<Diagnostic> {
    let text = match (snap.sourceFile(path)) {
        case Some(file) => file.text(snap.analysis).toString()
        case None => ""
    }
    let start = Position(line: 0, character: 0)
    [Diagnostic(range: LspRange(start: start, end: start), message: StringOrMarkupContent.AsString(text))]
}

func messageOf(diagnostic: Diagnostic): String {
    match (diagnostic.message) {
        case StringOrMarkupContent.AsString(text) => text
        case StringOrMarkupContent.AsMarkupContent(content) => content.value
    }
}

/**
 * `textAsDiagnostic`, parking its first call until `release` gets a value; every call is announced
 * on `entered` first, so a test knows it is running.
 */
class Parked {
    let entered = LinkedBlockingQueue<Bool>()
    let release = LinkedBlockingQueue<Bool>()
    private let parkNext = AtomicBool(true)

    func diagnostics(snap: ServerSnapshot, path: VfsPath): Array<Diagnostic> {
        entered.add(true)
        if (parkNext.swap(false)) {
            release.remove()
        }
        textAsDiagnostic(snap, path)
    }
}

func stateWith(text: String): ServerState {
    let state = ServerState()
    state.setFileContents(PUSHED_PATH, Rope(text))
    state
}

@Test
class DiagnosticsPushTest {
    @TestCase
    func aPublishOvertakenByANewerOneIsDropped() {
        // arrange
        let state = stateWith("a")
        let parked = Parked()
        let transport = WrittenTransport()
        let push = DiagnosticsPush(parked.diagnostics, clientOn(transport), NoopLogger())
        let older = push.schedule(state.snapshot(), [(PUSHED_PATH, 1)])
        parked.entered.remove()

        // act
        push.schedule(state.snapshot(), [(PUSHED_PATH, 2)]).get()
        parked.release.add(true)
        older.get()

        // assert
        @Expect(publishedOf(transport.nextNotification()).version, Some(Int32(2)))
        @Expect(transport.isEmpty())
    }

    @TestCase
    func aClosedDocumentIsClearedAtOnceAndWhatWasRunningForItDropped() {
        // arrange
        let state = stateWith("a")
        let parked = Parked()
        let transport = WrittenTransport()
        let push = DiagnosticsPush(parked.diagnostics, clientOn(transport), NoopLogger())
        let running = push.schedule(state.snapshot(), [(PUSHED_PATH, 1)])
        parked.entered.remove()

        // act
        push.clear(PUSHED_PATH)
        parked.release.add(true)
        running.get()

        // assert
        let cleared = publishedOf(transport.nextNotification())
        @Expect(cleared.uri, PUSHED_PATH.toUri())
        @Expect(cleared.diagnostics.size, 0)
        @Expect(transport.isEmpty())
    }
}

/**
 * A server whose `didOpen` and `didClose` only open and close the document, pushing
 * `textAsDiagnostic` when `pushes`.
 */
func pushingServer(transport: WrittenTransport, pushes: Bool): Server {
    let state = ServerState()
    state.pushesDiagnostics = pushes
    initialized(lifecycleRouter()
        .withState(state)
        .route(DidOpenTextDocumentNotificationSpec()) {
            ctx: Context<DidOpenTextDocumentParams> =>
                let path = VfsPath.fromUri(ctx.params.textDocument.uri)
                ctx.state.openDocuments.add(path, ctx.params.textDocument.version)
                ctx.state.setFileContents(path, Rope(ctx.params.textDocument.text))
        }
        .route(DidCloseTextDocumentNotificationSpec()) {
            ctx: Context<DidCloseTextDocumentParams> =>
                let path = VfsPath.fromUri(ctx.params.textDocument.uri)
                ctx.state.openDocuments.remove(path)
                ctx.state.setFileContents(path, Option<Rope>.None)
        }
        .publishDiagnostics(textAsDiagnostic), client: clientOn(transport))
}

func open(server: Server, text: String): Unit {
    let params = DidOpenTextDocumentParams(textDocument: TextDocumentItem(uri: PUSHED_PATH.toUri(),
        languageId: LanguageKind("cangjie"), version: 7, text: text))
    server.onNotification(DidOpenTextDocumentNotificationSpec.METHOD,
        ArrayOrObject.Object(params.serialize().asStructOrThrow()))
}

func close(server: Server): Unit {
    let params = DidCloseTextDocumentParams(textDocument: TextDocumentIdentifier(uri: PUSHED_PATH.toUri()))
    server.onNotification(DidCloseTextDocumentNotificationSpec.METHOD,
        ArrayOrObject.Object(params.serialize().asStructOrThrow()))
}

@Test
class ServerPushTest {
    @TestCase
    func aClientThatCannotPullIsPushedAnOpenDocumentAsItIsNow() {
        // arrange
        let transport = WrittenTransport()
        let server = pushingServer(transport, true)

        // act
        open(server, "class A {")

        // assert
        let pushed = publishedOf(transport.nextNotification())
        @Expect(pushed.uri, PUSHED_PATH.toUri())
        @Expect(pushed.version, Some(Int32(7)))
        @Expect(messageOf(pushed.diagnostics[0]), "class A {")
    }

    @TestCase
    func aClientThatPullsIsNeverPushedTo() {
        // arrange - the push is decided on the read loop, so nothing scheduled is nothing written
        let transport = WrittenTransport()
        let server = pushingServer(transport, false)

        // act
        open(server, "class A {")
        close(server)

        // assert
        @Expect(transport.isEmpty())
    }

    @TestCase
    func aDocumentClosedIsPushedNothingAtOnce() {
        // arrange
        let transport = WrittenTransport()
        let server = pushingServer(transport, true)
        open(server, "class A {")
        transport.nextNotification()

        // act
        close(server)

        // assert
        let cleared = publishedOf(transport.nextNotification())
        @Expect(cleared.uri, PUSHED_PATH.toUri())
        @Expect(cleared.diagnostics.size, 0)
    }
}
