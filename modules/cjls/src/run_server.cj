package cjls

import std.env.{getStdIn, getStdOut}
import std.io.*
import lsp.*
import cjls.lsp_types.*

func runServer(): Unit {
    logInfo("starting server")
    // let connection = Connection.stdio()
    // let caps = ServerCapabilities()
    // let initParams = connection.initialize(toLspAny(caps))
    // mainLoop(connection, initParams)
    logInfo("shutting down server")
}

// 
// func mainLoop<I, O>(conn: Connection<I, O>, initParams: LspAny): Unit where I <: InputStream, O <: OutputStream {
//     let _ = fromLspAny<InitializeParams>(initParams)
//     let docs = Documents()
//     while (let Some(msg) <- Message.read(conn.input)) {
//         match (msg) {
//             case Request(req) =>
//                 if (conn.handleShutdown(req)) {
//                     break
//                 }
//                 handleRequest(conn, req, docs)
//             case Notification(note) => handleNotification(conn, note, docs)
//             case Response(resp) => logError("response: ${resp}")
//         }
//     }
// }

// struct Connection<I, O> where I <: InputStream, O <: OutputStream {
//     
//     Connection(let input: BufferedInputStream<I>, let output: BufferedOutputStream<O>) {}

//     
//     static func stdio() {
//         Connection(BufferedInputStream(getStdIn()), BufferedOutputStream(getStdOut()))
//     }

//     
//     func initialize(serverCaps: LspAny): LspAny {
//         let (id, params) = initializeStart()
//         initializeFinish(id, serverCaps)
//         params
//     }

//     
//     func initializeStart(): (RequestId, LspAny) {
//         initializeStartWhile {=> true}
//     }

//     /**
//      * @throws ProtocolStateException - if lsp invariants are broken
//      */
//     
//     func initializeStartWhile(running: () -> Bool): (RequestId, LspAny) {
//         while (running()) {
//             let msg = try {
//                 Message.read(input) ?? throw ProtocolStateException(
//                     "connection closed before receiving initialize request")
//             } catch (e: JsonRpcProtocolException) {
//                 let resp = ResponseMessage(None, Err(ResponseError(ParseError, "Parse error: ${e.message}")))
//                 resp.write(output)
//                 continue
//             } catch (e: JsonRpcContentTruncatedException) {
//                 let resp = ResponseMessage(None, Err(ResponseError(ParseError, "Content truncated: ${e.message}")))
//                 resp.write(output)
//                 continue
//             }

//             match (msg) {
//                 case Request(req) where req.isInitialize => return (req.id, req.params.getOrDefault {=> LspNull})
//                 // Respond to non-initialize requests with ServerNotInitialized
//                 case Request(req) =>
//                     let resp = ResponseMessage.initErr(req.id, ServerNotInitialized, "expected initialize request")
//                     resp.write(output)
//                     continue
//                 case Notification(note) where !note.isExit => continue
//                 case msg => throw ProtocolStateException("unexpected message during initialize handshake: ${msg}")
//             }
//         }

//         throw ProtocolStateException("initialize handshake interrupted")
//     }

//     /**
//      * @throws ProtocolStateException - if client doesn't send `initialized` notification
//      */
//     
//     func initializeFinish(id: RequestId, initializeResult: LspAny): Unit {
//         let response = ResponseMessage.initOk(id, initializeResult)
//         response.write(output)

//         match (Message.read(input)) {
//             case Some(Notification(note)) where note.isInitialized => ()
//             case Some(msg) => throw ProtocolStateException(
//                 "expected 'initialized' notification after initialize response, got: ${msg}")
//             case None => throw ProtocolStateException("connection closed before receiving 'initialized' notification")
//         }
//     }

//     /**
//      * If `req` is `Shutdown`, respond to it and return `true`, otherwise return `false`
//      * @throws ProtocolStateException - if connection is closed before exit notification is sent or got an incorrect message
//      */
//     
//     func handleShutdown(req: RequestMessage): Bool {
//         if (!req.isShutdown) {
//             return false
//         }
//         let resp = ResponseMessage.initOk(req.id, LspNull)
//         resp.write(output)
//         let msg = Message.read(input) ?? throw ProtocolStateException(
//             "connection closed before receiving 'exit' notification after shutdown")
//         match (msg) {
//             case Notification(note) where note.isExit => ()
//             case msg => throw ProtocolStateException("expected 'exit' notification after shutdown, got: ${msg}")
//         }

//         true
//     }
// }

class ProtocolStateException <: Exception {
    ProtocolStateException(msg: String) {
        super(msg)
    }
}
