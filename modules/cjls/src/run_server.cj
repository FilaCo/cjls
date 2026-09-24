package cjls

import std.env.getStdOut
import stdx.log.getGlobalLogger
import jsonrpc.*
import cjls.server.*

/**
 * Serves stdio - stdout is the wire, so nothing else may write to it; logs go to stderr.
 *
 * @return the process exit code
 */
func runServer(): Int64 {
    getGlobalLogger().info("starting server")
    let transport = FramedJsonRpcTransport(StdinStream(), getStdOut(), getGlobalLogger())
    let exitCode = serveLsp(transport, routes())
    getGlobalLogger().info("server stopped with exit code ${exitCode}")

    exitCode
}
