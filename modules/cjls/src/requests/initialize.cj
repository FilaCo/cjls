package cjls.requests

import stdx.encoding.json.stream.*
import stdxx.deriving.*
import cjls.lsp_types.*
import cjls.macros.*
import lsp.*

@LspRequest["initialize", params: InitializeParams, result: InitializeResult]
public class Initialize {
    @LspHandle
    public static func handle(params: InitializeParams): InitializeResult {
        throw UnsupportedException() // TODO: implement
    }
}

@DeriveExt[Json]
public struct InitializeParams {
    public InitializeParams(
        /**
         * The process Id of the parent process that started the server. Is None if
         * the process has not been started by another process. If the parent
         * process is not alive then the server should exit (see exit notification)
         * its process.
         */
        public let processId: ?Int64,
        /**
         * The capabilities provided by the client (editor or tool)
         */
        public let capabilities: ClientCapabilities,
        /**
         * Information about the client
         *
         * @since 3.15.0
         */
        public let clientInfo!: ?ClientInfo = None,
        /**
         * The locale the client is currently showing the user interface
         * in. This must not necessarily be the locale of the operating
         * system.
         *
         * Uses IETF language tags as the value's syntax
         * (See https://en.wikipedia.org/wiki/IETF_language_tag)
         *
         * @since 3.16.0
         */
        public let locale!: ?String = None,
        /**
         * User provided initialization options.
         */
        public let initializationOptions!: ?LspAny = None,
        /**
         * The initial trace setting. If omitted trace is disabled ('off').
         */
        public let trace!: ?TraceValue = None,
        /**
         * The workspace folders configured in the client when the server starts.
         * This property is only available if the client supports workspace folders.
         * It can be `None` if the client supports workspace folders but none are
         * configured.
         *
         * @since 3.6.0
         */
        public let workspaceFolders!: ?Array<WorkspaceFolder> = None
    ) {}
}

@DeriveExt[Json]
public struct InitializeResult {
    public InitializeResult(
        /**
         * The capabilities the language server provides.
         */
        public let capabilities: ServerCapabilities,
        /**
         * Information about the server.
         *
         * @since 3.15.0
         */
        public let serverInfo!: ?ServerInfo = None) {}
}
