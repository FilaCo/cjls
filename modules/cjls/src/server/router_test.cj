package cjls.server

import std.collection.concurrent.LinkedBlockingQueue
import std.sync.AtomicBool
import std.unittest.*
import std.unittest.testmacro.*
import stdx.encoding.json.*
import stdx.serialization.serialization.*
import stdxx.*
import jsonrpc.*
import cjls.lsp_types.*

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
    let json = ##"{"processId": null, "rootUri": null, "capabilities": {}}"##
    ArrayOrObject.Object(DataModel.fromJson(JsonValue.fromStr(json)).asStructOrThrow())
}

/**
 * The lifecycle's own handlers, doing nothing but answering.
 */
func lifecycleRoutes(): Routes {
    Routes()
        .route(InitializeRequestSpec()) {_ => InitializeResult(capabilities: ServerCapabilities())}
        .route(ShutdownRequestSpec()) {_ => ()}
}

func routerOf(routes: Routes): Router {
    Router(routes, Client())
}

func initialized(routes: Routes): Router {
    let router = routerOf(routes)
    let asked = Asked(InitializeRequestSpec.METHOD, params: initializeParams())
    router.onRequest(asked.request)
    asked.answer().getResultOrThrow()
    router
}

@Test
class RouterLifecycleTest {
    @TestCase
    func aRequestBeforeInitializeIsRefused() {
        // arrange
        let router = routerOf(lifecycleRoutes())
        let asked = Asked(ShutdownRequestSpec.METHOD)

        // act
        router.onRequest(asked.request)

        // assert
        @Expect(ErrorCode.SERVER_NOT_INITIALIZED, asked.answer().getErrorOrThrow().code)
    }

    @TestCase
    func aNotificationBeforeInitializeIsDropped() {
        // arrange - a `route` handler runs within `onNotification`, so once it returns the
        // handler has either run or never will
        let ran = AtomicBool(false)
        let router = routerOf(lifecycleRoutes().route(InitializedNotificationSpec()) {_ => ran.store(true)})

        // act
        router.onNotification(InitializedNotificationSpec.METHOD, ArrayOrObject.Object(DataModelStruct()))

        // assert
        @Expect(!ran.load())
    }

    @TestCase
    func aSuccessfulInitializeStartsTheServer() {
        // act
        let router = initialized(lifecycleRoutes())

        // assert
        @Expect(match (router.state) {
            case Initialized => true
            case _ => false
        })
    }

    @TestCase
    func aFailedInitializeLeavesTheServerUninitialized() {
        // arrange - `capabilities` is required, so these params do not decode
        let router = routerOf(lifecycleRoutes())
        let asked = Asked(InitializeRequestSpec.METHOD, params: ArrayOrObject.Object(DataModelStruct()))

        // act
        router.onRequest(asked.request)

        // assert
        @Expect(ErrorCode.INVALID_PARAMS, asked.answer().getErrorOrThrow().code)
        @Expect(match (router.state) {
            case Uninitialized => true
            case _ => false
        })
    }

    @TestCase
    func aSecondInitializeIsRefused() {
        // arrange
        let router = initialized(lifecycleRoutes())
        let asked = Asked(InitializeRequestSpec.METHOD, params: initializeParams())

        // act
        router.onRequest(asked.request)

        // assert
        @Expect(ErrorCode.INVALID_REQUEST, asked.answer().getErrorOrThrow().code)
    }

    @TestCase
    func aRequestAfterShutdownIsRefused() {
        // arrange
        let router = initialized(lifecycleRoutes())
        let shutdown = Asked(ShutdownRequestSpec.METHOD)
        router.onRequest(shutdown.request)
        let again = Asked(ShutdownRequestSpec.METHOD)

        // act
        router.onRequest(again.request)

        // assert
        @Expect(shutdown.answer().getResultOrThrow() is DataModelNull)
        @Expect(ErrorCode.INVALID_REQUEST, again.answer().getErrorOrThrow().code)
    }

    @TestCase
    func exitAfterShutdownExitsCleanly() {
        // arrange
        let router = initialized(lifecycleRoutes())
        let shutdown = Asked(ShutdownRequestSpec.METHOD)
        router.onRequest(shutdown.request)
        shutdown.answer()

        // act
        router.onNotification(ExitNotificationSpec.METHOD, Option<ArrayOrObject>.None)

        // assert
        @Expect(0, router.exitCode)
        @Expect(match (router.state) {
            case Exited => true
            case _ => false
        })
    }

    @TestCase
    func exitWithoutShutdownExitsWithAnError() {
        // arrange - `exit` is honoured in any state, even before `initialize`
        let router = routerOf(lifecycleRoutes())

        // act
        router.onNotification(ExitNotificationSpec.METHOD, Option<ArrayOrObject>.None)

        // assert
        @Expect(1, router.exitCode)
    }
}

@Test
class RouterDispatchTest {
    @TestCase
    func anUnknownMethodIsNotFound() {
        // arrange
        let router = initialized(lifecycleRoutes())
        let asked = Asked("textDocument/hover")

        // act
        router.onRequest(asked.request)

        // assert
        @Expect(ErrorCode.METHOD_NOT_FOUND, asked.answer().getErrorOrThrow().code)
    }

    @TestCase
    func aReadOnlyRequestIsAnsweredFromAThreadOfItsOwn() {
        // arrange - the handler parks until released; `onRequest` returning while it is parked
        // shows it did not run on the calling thread
        let release = LinkedBlockingQueue<Bool>()
        let router = initialized(lifecycleRoutes().readonly(HoverRequestSpec()) {
            _ =>
                release.remove()
                Nullable<Hover>.Null
        })
        let asked = Asked(HoverRequestSpec.METHOD, params: hoverParams())

        // act
        router.onRequest(asked.request)
        @Expect(!asked.request.isAnswered)
        release.add(true)

        // assert
        @Expect(asked.answer().getResultOrThrow() is DataModelNull)
    }

    @TestCase
    func aHandlerSeesItsParamsAndTheCancellationOfItsOwnRequest() {
        // arrange
        let router = initialized(lifecycleRoutes().route(HoverRequestSpec()) {
            ctx => Nullable.Value(Hover(contents: MarkupContentOrMarkedStringOrMarkedStrings.AsMarkupContent(
                MarkupContent(kind: MarkupKind.PlainText,
                    value: "${ctx.params.position.line}:${ctx.cancellation.isCancelled}"))))
        })
        let asked = Asked(HoverRequestSpec.METHOD, params: hoverParams())
        asked.request.cancellation.cancel()

        // act
        router.onRequest(asked.request)

        // assert
        let contents = asked.answer().getResultOrThrow().asStructOrThrow().getOrThrow("contents").asStructOrThrow()
        @Expect("3:true", contents.getOrThrow("value").asStringOrThrow())
    }

    @TestCase
    func paramsThatDoNotReadAreInvalidParams() {
        // arrange
        let router = initialized(lifecycleRoutes().route(HoverRequestSpec()) {_ => Nullable<Hover>.Null})
        let asked = Asked(HoverRequestSpec.METHOD, params: ArrayOrObject.Object(DataModelStruct()))

        // act
        router.onRequest(asked.request)

        // assert
        @Expect(ErrorCode.INVALID_PARAMS, asked.answer().getErrorOrThrow().code)
    }

    @TestCase
    func aHandlerThatThrowsAnswersWithItsError() {
        // arrange
        let router = initialized(Routes()
            .route(InitializeRequestSpec()) {_ => InitializeResult(capabilities: ServerCapabilities())}
            .route(ShutdownRequestSpec()) {_ => throw RpcException(ErrorCode.UNKNOWN_ERROR_CODE, "no")})
        let asked = Asked(ShutdownRequestSpec.METHOD)

        // act
        router.onRequest(asked.request)

        // assert
        @Expect(ErrorCode.UNKNOWN_ERROR_CODE, asked.answer().getErrorOrThrow().code)
    }
}

@Test
class RoutesTest {
    @TestCase
    func twoHandlersForOneMethodAreRefused() {
        // act & assert
        @AssertThrows[IllegalArgumentException](lifecycleRoutes().route(ShutdownRequestSpec()) {_ => ()})
    }

    @TestCase
    func aLifecycleMethodHandledOffTheReadLoopIsRefused() {
        // act & assert - whatever arrives after `shutdown` has to see the state it leaves
        @AssertThrows[IllegalArgumentException](Routes().readonly(ShutdownRequestSpec()) {_ => ()})
    }
}
