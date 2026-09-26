package cjls.server

import std.collection.concurrent.LinkedBlockingQueue
import std.sync.AtomicBool
import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.NoopLogger
import stdx.serialization.serialization.*
import jsonrpc.*
import cjls.lsp_types.*

/**
 * A transport that only takes what is written, so a test can wait for it; nothing is ever read.
 */
class WrittenTransport <: JsonRpcTransport {
    private let written = LinkedBlockingQueue<Body>()
    private let closed = AtomicBool(false)

    /**
     * Blocks until something is written, so no test has to poll a spawned publish.
     */
    func nextNotification(): NotificationBody {
        written.remove().getNotificationBodyOrThrow()
    }

    /**
     * Whether nothing was written that was not taken.
     */
    func isEmpty(): Bool {
        written.size == 0
    }

    public func isClosed(): Bool {
        closed.load()
    }

    public func close(): Unit {
        closed.store(true)
    }

    public func read(): ?Body {
        None
    }

    public func write(body: Body): Unit {
        written.add(body)
    }
}

/**
 * A client connected to `transport`, answering nothing.
 */
func clientOn(transport: WrittenTransport): Client {
    let client = Client()
    client.connect(Connection(transport, serverOf(Router()), NoopLogger()))
    client
}

func publishedOf(notification: NotificationBody): PublishDiagnosticsParams {
    PublishDiagnosticsParams.deserialize(notification.params.getOrThrow().serialize())
}

@Test
class ClientTest {
    @TestCase
    func aNotificationGoesByTheMethodOfItsSpec() {
        // arrange
        let transport = WrittenTransport()
        let client = clientOn(transport)

        // act
        client.notify(PublishDiagnosticsNotificationSpec(), PublishDiagnosticsParams(uri: "file:///a.cj", diagnostics: []))

        // assert
        let sent = transport.nextNotification()
        @Expect(sent.method, "textDocument/publishDiagnostics")
        @Expect(publishedOf(sent).uri, "file:///a.cj")
    }

    @TestCase
    func aClientIsClosedOnceItsConnectionIs() {
        // arrange
        let transport = WrittenTransport()
        let client = clientOn(transport)
        let before = client.isClosed()

        // act
        client.close()

        // assert
        @Expect(!before)
        @Expect(client.isClosed())
    }

    @TestCase
    func aClientNotYetConnectedIsNotClosed() {
        // act
        let closed = Client().isClosed()

        // assert
        @Expect(!closed)
    }
}
