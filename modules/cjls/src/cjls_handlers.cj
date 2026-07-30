package cjls

import lsp.*
import cjls.lsp_types.*
import cjls.server.*
import cjls.requests.*
import cjls.notifications.*
import cjls.macros.*

public interface LspHandlers {
    static func dispatchRequest(msg: RequestMessage, ctx: GlobalContext): ResponseMessage
    static func dispatchNotification(msg: NotificationMessage, ctx: GlobalContext): Unit
    static prop SERVER_CAPABILITIES: ServerCapabilities
}

@LspHandlers[
    requests: [
        Initialize,
        Shutdown
    ],
    notifications: [
        Initialized,
        Exit,
        DidOpenTextDocument
    ]
]
class CjlsHandlers {}
