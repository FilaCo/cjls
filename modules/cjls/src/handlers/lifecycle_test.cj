package cjls.handlers

import std.collection.ArrayList
import std.io.ByteBuffer
import stdx.serialization.serialization.*
import stdx.log.NoopLogger
import stdxx.{IntegerOrString, Nullable}
import stdxx.serialization.*
import rope.Encoding
import jsonrpc.*
import cjls.lsp_types.*
import cjls.server.*

private func framed(json: String): String {
    "Content-Length: ${json.size}\r\n\r\n${json}"
}

/**
 * Serves a whole session fed up front: every handler it reaches is a `route` one, so each answer is
 * written before the next message is read, and the loop ends on the buffer running dry.
 */
private func session(messages: Array<String>): (Int64, Array<ResponseBody>) {
    let input = ByteBuffer()
    for (message in messages) {
        input.write(framed(message).toArray())
    }
    let output = ByteBuffer()

    let exitCode = serve(FramedJsonRpcTransport(input, output, NoopLogger()), router(), NoopLogger())

    let responses = FramedJsonRpcTransport(output, ByteBuffer(), NoopLogger())
    let bodies = ArrayList<ResponseBody>()
    while (let Some(body) <- responses.read()) {
        bodies.add(body.getResponseBodyOrThrow())
    }
    (exitCode, bodies.toArray())
}

@Test
class LifecycleTest {
    @TestCase
    func aWholeSessionShutsDownCleanly() {
        // act
        let (exitCode, responses) = session([
            ##"{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"processId": null, "rootUri": null, "capabilities": {}}}"##,
            ##"{"jsonrpc": "2.0", "method": "initialized", "params": {}}"##,
            ##"{"jsonrpc": "2.0", "id": 2, "method": "shutdown"}"##,
            ##"{"jsonrpc": "2.0", "method": "exit"}"##
        ])

        // assert
        @Expect(0, exitCode)
        @Expect(2, responses.size)
        let serverInfo = responses[0].resultOrError.getResultOrThrow().asStructOrThrow().getOrThrow("serverInfo")
        @Expect("cjls", serverInfo.asStructOrThrow().getOrThrow("name").asStringOrThrow())
        @Expect(Integer(2), responses[1].id.getOrThrow())
        @Expect(responses[1].resultOrError.getResultOrThrow() is DataModelNull)
    }

    @TestCase
    func aHangUpWithoutExitIsNoCleanExit() {
        // act
        let (exitCode, _) = session([
            ##"{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"processId": null, "rootUri": null, "capabilities": {}}}"##
        ])

        // assert
        @Expect(1, exitCode)
    }
}

@Test
class InitializeTest {
    /**
     * `(what the client offers, what is agreed on, how it is advertised)`: UTF-8 if offered, else
     * the UTF-16 every client can count in.
     */
    @TestCase[row in [
        (ClientCapabilities(general: GeneralClientCapabilities(
            positionEncodings: [PositionEncodingKind.UTF16, PositionEncodingKind.UTF8])), Encoding.Utf8, "utf-8"),
        (ClientCapabilities(general: GeneralClientCapabilities(positionEncodings: [PositionEncodingKind.UTF16])),
            Encoding.Utf16, "utf-16"),
        (ClientCapabilities(), Encoding.Utf16, "utf-16")
    ]]
    func theEncodingIsUtf8WhenTheClientOffersItElseUtf16(row: (ClientCapabilities, Encoding, String)) {
        // arrange
        let (capabilities, expected, advertised) = row
        let state = ServerState()

        // act
        let result = handleInitialize(state, InitializeParams(processId: Nullable.Null, rootUri: Nullable.Null,
            capabilities: capabilities))

        // assert
        @Expect(state.encoding, expected)
        @Expect(result.capabilities.positionEncoding?.value, Some(advertised))
    }
}
