package lsp_codegen

import std.fs.Path
import std.io.{ByteBuffer, readToEnd}
import std.unittest.*
import std.unittest.testmacro.*

private func resolveMessagesOf(requests!: Array<Request> = [], notifications!: Array<Notification> = []): Array<
    MessageIr> {
    let mm = MetaModel(metaData: MetaData(version: "3.18.0"), requests: requests, notifications: notifications,
        structures: [], enumerations: [], typeAliases: [])
    let resolver = TypeResolver(mm, Config(srcDir: Path("src"), outputPackage: "demo.lsp_types", typeMap: TypeMap()))

    resolveMessages(resolver, mm)
}

private func requestOf(method: String, typeName: String, result: Type, params!: ?OneOrMany<Type> = None): Request {
    Request(method: method, typeName: typeName, params: params, result: result,
        messageDirection: MessageDirection.ClientToServer)
}

private func emittedOf(messageIr: MessageIr): String {
    let buffer = ByteBuffer()
    let emitter = CjEmitter(buffer)
    emitter.emitMessage(messageIr)
    emitter.flush()
    unsafe { String.fromUtf8(readToEnd(buffer)) }
}

@Test
class ResolveMessagesTest {
    @TestCase
    func aRequestNamesItsParamsAndResultTypes() {
        // act
        let messages = resolveMessagesOf(
            requests: [requestOf("textDocument/hover", "HoverRequest",
                Type.Or([Type.Reference("Hover"), Type.Base(BaseTypes.Null)]),
                params: OneOrMany.One(Type.Reference("HoverParams")))])

        // assert - a result that may be `null` is a `Nullable`, like any other such type
        @Expect("HoverRequestSpec", messages[0].ident)
        @Expect("textDocument/hover", messages[0].method)
        @Expect("HoverParams", messages[0].paramsType)
        @Expect("Nullable<Hover>", messages[0].resultType)
    }

    @TestCase
    func noParamsAndANullResultAreBothUnit() {
        // act - `shutdown`: nothing in, a bare `null` out
        let messages = resolveMessagesOf(requests: [requestOf("shutdown", "ShutdownRequest", Type.Base(BaseTypes.Null))])

        // assert
        @Expect(messages[0].params.isNone())
        @Expect(messages[0].result.isNone())
        @Expect("Unit", messages[0].paramsType)
        @Expect("Unit", messages[0].resultType)
    }

    @TestCase
    func aNotificationHasNoResult() {
        // act
        let messages = resolveMessagesOf(
            notifications: [Notification(method: "exit", typeName: "ExitNotification",
                messageDirection: MessageDirection.ClientToServer)])

        // assert
        @Expect(!messages[0].isRequest)
        @Expect("Unit", messages[0].paramsType)
    }

    @TestCase
    func positionalParamsAreRefused() {
        // act & assert - a struct is no fit for them, and LSP 3.x declares none
        @AssertThrows[IllegalStateException](resolveMessagesOf(
            requests: [requestOf("odd", "OddRequest", Type.Base(BaseTypes.Null),
                params: OneOrMany.Many([Type.Reference("A"), Type.Reference("B")]))]))
    }

    @TestCase
    func aMessageIsEmittedAsASpecOfItsTypes() {
        // arrange
        let messageIr = MessageIr(DocIr(), ident: "HoverRequestSpec", method: "textDocument/hover",
            direction: MessageDirection.ClientToServer, params: TypeIr.Named("HoverParams"),
            result: TypeIr.NullableOf(TypeIr.Named("Hover")), isRequest: true)
        let buffer = ByteBuffer()
        let emitter = CjEmitter(buffer)

        // act
        emitter.emitMessage(messageIr)
        emitter.flush()
        let emitted = unsafe { String.fromUtf8(readToEnd(buffer)) }

        // assert
        @Expect(emitted.contains("public struct HoverRequestSpec <: LspInboundRequest<HoverParams, Nullable<Hover>> {"))
        @Expect(emitted.contains("\"textDocument/hover\""))
        @Expect(emitted.contains("MessageDirection.ClientToServer"))
        @Expect(emitted.contains("decodeMessageParams<HoverParams>(params)"))
        @Expect(emitted.contains("public func encodeResult(result: Nullable<Hover>): DataModel {"))
    }

    @TestCase
    func aMessageWithoutParamsOrResultIsBoundToUnit() {
        // arrange - `shutdown`
        let messageIr = MessageIr(DocIr(), ident: "ShutdownRequestSpec", method: "shutdown",
            direction: MessageDirection.ClientToServer, isRequest: true)

        // act
        let emitted = emittedOf(messageIr)

        // assert - nothing to decode, and `null` is the whole answer
        @Expect(emitted.contains("LspInboundRequest<Unit, Unit>"))
        @Expect(emitted.contains("public func decodeParams(params: ?ArrayOrObject): Unit {"))
        @Expect(emitted.contains("DataModelNull()"))
    }

    @TestCase
    func aMessageTheServerSendsHasNothingToBind() {
        // arrange
        let messageIr = MessageIr(DocIr(), ident: "ShowMessageNotificationSpec", method: "window/showMessage",
            direction: MessageDirection.ServerToClient, params: TypeIr.Named("ShowMessageParams"), isRequest: false)

        // act
        let emitted = emittedOf(messageIr)

        // assert
        @Expect(emitted.contains("LspOutboundNotification<ShowMessageParams>"))
        @Expect(!emitted.contains("decodeParams"))
    }

    @TestCase
    func aMessageSentBothWaysIsBothInboundAndOutbound() {
        // arrange - `$/progress`
        let messageIr = MessageIr(DocIr(), ident: "ProgressNotificationSpec", method: "$/progress",
            direction: MessageDirection.Both, params: TypeIr.Named("ProgressParams"), isRequest: false)
        let buffer = ByteBuffer()
        let emitter = CjEmitter(buffer)

        // act
        emitter.emitMessage(messageIr)
        emitter.flush()
        let emitted = unsafe { String.fromUtf8(readToEnd(buffer)) }

        // assert
        @Expect(emitted.contains(
            "ProgressNotificationSpec <: LspInboundNotification<ProgressParams> & LspOutboundNotification<ProgressParams>"))
    }
}
