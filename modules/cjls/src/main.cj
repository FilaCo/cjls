package cjls

import std.env.getStdOut
import jsonrpc.FramedJsonRpcTransport
import cjls.server.serve
import cjls.handlers.router

main(): Int64 {
    let logger = stderrLogger()
    try {
        useBinaryStdio()
        // stdout is the wire: nothing else may write to it
        let exitCode = serve(FramedJsonRpcTransport(StdinStream(), getStdOut(), logger), router(), logger)
        logger.info("stopped", [("exitCode", exitCode)])
        exitCode
    } catch (e: Exception) {
        logger.fatal("stopped", [("cause", e)])
        1
    }
}
