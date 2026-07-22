package cjls

import std.env.{getStdIn, getStdOut}
import std.io.*
import lsp.*

@Frozen
func runServer(): Unit {
    logInfo("starting server")
    let connection = Connection.stdio()
    let caps = ServerCapabilities()
    let initParams = connection.initialize(toLspAny(caps))
    mainLoop(connection, initParams)
    logInfo("shutting down server")
}

@Frozen
func mainLoop<I, O>(conn: Connection<I, O>, initParams: LspAny): Unit where I <: InputStream, O <: OutputStream {
    let _ = fromLspAny<InitializeParams>(initParams)
    let docs = Documents()
    while (let Some(msg) <- Message.read(conn.input)) {
        match (msg) {
            case Request(req) =>
                if (conn.handleShutdown(req)) {
                    break
                }
                handleRequest(conn, req, docs)
            case Notification(note) => handleNotification(conn, note, docs)
            case Response(resp) => logError("response: ${resp}")
        }
    }
}

struct Connection<I, O> where I <: InputStream, O <: OutputStream {
    @Frozen
    Connection(let input: BufferedInputStream<I>, let output: BufferedOutputStream<O>) {}

    @Frozen
    static func stdio() {
        Connection(BufferedInputStream(getStdIn()), BufferedOutputStream(getStdOut()))
    }

    @Frozen
    func initialize(serverCaps: LspAny): LspAny {
        let (id, params) = initializeStart()
        initializeFinish(id, serverCaps)
        params
    }

    @Frozen
    func initializeStart(): (RequestId, LspAny) {
        initializeStartWhile {=> true}
    }

    @Frozen
    func initializeStartWhile(running: () -> Bool): (RequestId, LspAny) {
        while (running()) {
            let msg = Message.read(input) ?? throw Exception() // TODO: custom exception

            match (msg) {
                case Request(req) where req.isInitialize => return (req.id, req.params.getOrDefault {=> LspNull})
                // Respond to non-initialize requests with ServerNotInitialized
                case Request(req) =>
                    let resp = ResponseMessage.initErr(req.id, ServerNotInitialized, "expected initialize request")
                    resp.write(output)
                    continue
                case Notification(note) where !note.isExit => continue
                case msg => throw Exception() // TODO: custom exception
            }
        }

        throw Exception() //TODO: custom exception
    }

    @Frozen
    func initializeFinish(id: RequestId, initializeResult: LspAny): Unit {
        let response = ResponseMessage.initOk(id, initializeResult)
        response.write(output)

        match (Message.read(input)) {
            case Some(Notification(note)) where note.isInitialized => ()
            case Some(msg) => throw Exception() //TODO: custom exception
            case None => throw Exception() // TODO: Exception
        }
    }

    /**
     * If `req` is `Shutdown`, respond to it and return `true`, otherwise return `false`
     */
    @Frozen
    func handleShutdown(req: RequestMessage): Bool {
        if (!req.isShutdown) {
            return false
        }
        let resp = ResponseMessage.initOk(req.id, LspNull)
        resp.write(output)
        let msg = Message.read(input) ?? throw Exception() // TODO: custom exception
        match (msg) {
            case Notification(note) where note.isExit => ()
            case msg => throw Exception() // TODO: custom exception
        }

        true
    }
}

class ProtocolStateException <: Exception {}

private func handleRequest<I, O>(conn: Connection<I, O>, req: RequestMessage, docs: Documents): Unit where I <: InputStream,
    O <: OutputStream {}

private func handleNotification<I, O>(conn: Connection<I, O>, note: NotificationMessage, docs: Documents): Unit where I <: InputStream,
    O <: OutputStream {}
