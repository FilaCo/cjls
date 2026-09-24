package cjls.server

import stdx.log.getGlobalLogger
import jsonrpc.*

/**
 * Runs a language server over `transport` until the client hangs up or sends `exit`.
 *
 * @return the exit code the protocol asks for: `0` for an `exit` after a `shutdown`, `1` otherwise
 * @throws TransportException - if the framing is lost in either direction
 */
public func serveLsp(transport: JsonRpcTransport, routes: Routes): Int64 {
    let client = Client()
    let router = Router(routes, client)
    let connection = Connection(transport, router, getGlobalLogger())
    client.connect(connection)
    connection.serve()

    router.exitCode
}
