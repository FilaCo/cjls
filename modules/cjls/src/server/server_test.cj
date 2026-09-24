package cjls.server

import std.collection.concurrent.LinkedBlockingQueue
import std.sync.AtomicBool
import std.unittest.*
import std.unittest.testmacro.*
import stdx.encoding.json.*
import stdx.log.NoopLogger
import stdx.serialization.serialization.*
import stdxx.{IntegerOrString, Nullable}
import stdxx.serialization.*
import jsonrpc.*
import cjls.lsp_types.*
import cjls.macros.LspHandler

/**
 * A request as the connection would hand it over, with its answer caught on a queue so a test can
 * wait for one given off-thread.
 */
class Asked {
    let answers = LinkedBlockingQueue<ResultOrError>()
    let request: InboundRequest

    init(method: String, params!: ?ArrayOrObject = Option<ArrayOrObject>.None) {
        let answers = this.answers
        request = InboundRequest(Integer(1), method, params, CancellationToken(), {answer => answers.add(answer)})
    }

    func answer(): ResultOrError {
        answers.remove()
    }
}

func paramsOf(json: String): ArrayOrObject {
    ArrayOrObject.Object(DataModel.fromJson(JsonValue.fromStr(json)).asStructOrThrow())
}

func hoverParams(): ArrayOrObject {
    paramsOf(##"{"textDocument": {"uri": "file:///a.cj"}, "position": {"line": 3, "character": 1}}"##)
}

func initializeParams(): ArrayOrObject {
    paramsOf(##"{"processId": null, "rootUri": null, "capabilities": {}}"##)
}

/**
 * The lifecycle's own handlers, doing nothing but answering.
 */
func lifecycleRouter(): Router {
    Router()
        .route(InitializeRequestSpec()) {_: Context<InitializeParams> => InitializeResult(capabilities: ServerCapabilities())}
        .route(ShutdownRequestSpec()) {_: Context<Unit> => ()}
}

func serverOf(router: Router, client!: Client = Client()): Server {
    Server(router, client, NoopLogger())
}

func initialized(router: Router, client!: Client = Client()): Server {
    let server = serverOf(router, client: client)
    let asked = Asked(InitializeRequestSpec.METHOD, params: initializeParams())
    server.onRequest(asked.request)
    asked.answer().getResultOrThrow()
    server
}

let describedClients = LinkedBlockingQueue<Client>()

/**
 * Tells what it was given: the line and the cancellation in its answer, the client on a queue.
 */
@LspHandler[readonly]
func describeHover(client: Client, cancellation: CancellationToken, params: HoverParams): Nullable<Hover> {
    describedClients.add(client)
    let described = "${params.position.line}:${cancellation.isCancelled}"
    Nullable.Value(Hover(contents: MarkupContentOrMarkedStringOrMarkedStrings.AsMarkupContent(
        MarkupContent(kind: MarkupKind.PlainText, value: described))))
}

@Test
class ServerLifecycleTest {
    @TestCase
    func aRequestBeforeInitializeIsRefused() {
        // arrange
        let server = serverOf(lifecycleRouter())
        let asked = Asked(ShutdownRequestSpec.METHOD)

        // act
        server.onRequest(asked.request)

        // assert
        @Expect(ErrorCode.SERVER_NOT_INITIALIZED, asked.answer().getErrorOrThrow().code)
    }

    @TestCase
    func aNotificationBeforeInitializeIsDropped() {
        // arrange - a `route` handler runs within `onNotification`: once that returns, it has run or never will
        let ran = AtomicBool(false)
        let server = serverOf(lifecycleRouter().route(InitializedNotificationSpec()) {_: Context<InitializedParams> => ran.store(true)})

        // act
        server.onNotification(InitializedNotificationSpec.METHOD, ArrayOrObject.Object(DataModelStruct()))

        // assert
        @Expect(!ran.load())
    }

    @TestCase
    func aSuccessfulInitializeStartsTheServer() {
        // act
        let server = initialized(lifecycleRouter())

        // assert
        @Expect(match (server.state) {
            case Initialized => true
            case _ => false
        })
    }

    @TestCase
    func aFailedInitializeLeavesTheServerUninitialized() {
        // arrange - `capabilities` is required, so these params do not decode
        let server = serverOf(lifecycleRouter())
        let asked = Asked(InitializeRequestSpec.METHOD, params: ArrayOrObject.Object(DataModelStruct()))

        // act
        server.onRequest(asked.request)

        // assert
        @Expect(ErrorCode.INVALID_PARAMS, asked.answer().getErrorOrThrow().code)
        @Expect(match (server.state) {
            case Uninitialized => true
            case _ => false
        })
    }

    @TestCase
    func aSecondInitializeIsRefused() {
        // arrange
        let server = initialized(lifecycleRouter())
        let asked = Asked(InitializeRequestSpec.METHOD, params: initializeParams())

        // act
        server.onRequest(asked.request)

        // assert
        @Expect(ErrorCode.INVALID_REQUEST, asked.answer().getErrorOrThrow().code)
    }

    @TestCase
    func aRequestAfterShutdownIsRefused() {
        // arrange
        let server = initialized(lifecycleRouter())
        let shutdown = Asked(ShutdownRequestSpec.METHOD)
        server.onRequest(shutdown.request)
        let again = Asked(ShutdownRequestSpec.METHOD)

        // act
        server.onRequest(again.request)

        // assert
        @Expect(shutdown.answer().getResultOrThrow() is DataModelNull)
        @Expect(ErrorCode.INVALID_REQUEST, again.answer().getErrorOrThrow().code)
    }

    @TestCase
    func exitAfterShutdownExitsCleanly() {
        // arrange
        let server = initialized(lifecycleRouter())
        let shutdown = Asked(ShutdownRequestSpec.METHOD)
        server.onRequest(shutdown.request)
        shutdown.answer()

        // act
        server.onNotification(ExitNotificationSpec.METHOD, Option<ArrayOrObject>.None)

        // assert
        @Expect(0, server.exitCode)
        @Expect(match (server.state) {
            case Exited => true
            case _ => false
        })
    }

    @TestCase
    func exitWithoutShutdownExitsWithAnError() {
        // arrange - `exit` is honoured in any state, even before `initialize`
        let server = serverOf(lifecycleRouter())

        // act
        server.onNotification(ExitNotificationSpec.METHOD, Option<ArrayOrObject>.None)

        // assert
        @Expect(1, server.exitCode)
    }
}

@Test
class ServerDispatchTest {
    @TestCase
    func anUnknownMethodIsNotFound() {
        // arrange
        let server = initialized(lifecycleRouter())
        let asked = Asked("textDocument/hover")

        // act
        server.onRequest(asked.request)

        // assert
        @Expect(ErrorCode.METHOD_NOT_FOUND, asked.answer().getErrorOrThrow().code)
    }

    @TestCase
    func aReadOnlyRequestIsAnsweredFromAThreadOfItsOwn() {
        // arrange - the handler parks until released; `onRequest` returning while it is parked
        // shows it did not run on the calling thread
        let release = LinkedBlockingQueue<Bool>()
        let server = initialized(lifecycleRouter().route(HoverRequestSpec()) {
            _: ReadOnlyContext<HoverParams> =>
                release.remove()
                Nullable<Hover>.Null
        })
        let asked = Asked(HoverRequestSpec.METHOD, params: hoverParams())

        // act
        server.onRequest(asked.request)
        @Expect(!asked.request.isAnswered)
        release.add(true)

        // assert
        @Expect(asked.answer().getResultOrThrow() is DataModelNull)
    }

    @TestCase
    func aHandlerGetsItsParamsAndWhatItAsksFor() {
        // arrange
        let client = Client()
        let server = initialized(lifecycleRouter().route(HoverRequestSpec(), describeHover), client: client)
        let asked = Asked(HoverRequestSpec.METHOD, params: hoverParams())
        asked.request.cancellation.cancel()

        // act
        server.onRequest(asked.request)

        // assert
        let contents = asked.answer().getResultOrThrow().asStructOrThrow().getOrThrow("contents").asStructOrThrow()
        @Expect("3:true", contents.getOrThrow("value").asStringOrThrow())
        @Expect(refEq(client, describedClients.remove()))
    }

    @TestCase
    func aHandlerThatThrowsAnswersWithItsError() {
        // arrange
        let server = initialized(Router()
            .route(InitializeRequestSpec()) {_: Context<InitializeParams> => InitializeResult(capabilities: ServerCapabilities())}
            .route(ShutdownRequestSpec()) {_: Context<Unit> => throw RpcException(ErrorCode.UNKNOWN_ERROR_CODE, "no")})
        let asked = Asked(ShutdownRequestSpec.METHOD)

        // act
        server.onRequest(asked.request)

        // assert
        @Expect(ErrorCode.UNKNOWN_ERROR_CODE, asked.answer().getErrorOrThrow().code)
    }

    @TestCase
    func aNotificationHandlerThatThrowsDoesNotStopTheServer() {
        // arrange
        let server = initialized(lifecycleRouter().route(InitializedNotificationSpec()) {_: Context<InitializedParams> => throw Exception("no")})

        // act
        server.onNotification(InitializedNotificationSpec.METHOD, ArrayOrObject.Object(DataModelStruct()))

        // assert
        @Expect(match (server.state) {
            case Initialized => true
            case _ => false
        })
    }
}

@Test
class RouterTest {
    @TestCase
    func twoHandlersForOneMethodAreRefused() {
        // act & assert
        @AssertThrows[IllegalArgumentException](lifecycleRouter().route(ShutdownRequestSpec()) {_: Context<Unit> => ()})
    }

    @TestCase
    func aLifecycleMethodHandledOffTheReadLoopIsRefused() {
        // act & assert - whatever arrives after `shutdown` has to see the state it leaves
        @AssertThrows[IllegalArgumentException](Router().route(ShutdownRequestSpec()) {_: ReadOnlyContext<Unit> => ()})
    }
}
