package cjls.server

import stdx.log.Logger
import jsonrpc.*

/**
 * Runs a language server over `transport` until the client hangs up or sends `exit`.
 *
 * @return the exit code the protocol asks for: `0` for an `exit` after a `shutdown`, `1` otherwise
 * @throws TransportException - if the framing is lost in either direction
 */
public func serve(transport: JsonRpcTransport, router: Router, logger: Logger): Int64 {
    let client = Client()
    let server = Server(router, client, logger)
    let connection = Connection(transport, server, logger)
    client.connect(connection)
    connection.serve()

    server.exitCode
}
