package cjls.lsp_types

import std.io.{InputStream, OutputStream}
import stdx.encoding.json.stream.*
import stdx.encoding.url.URL
import stdxx.deriving.*
import lsp.*

@DeriveExt[Json]
public struct InitializeParams {
    @Frozen
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
    @Frozen
    public InitializeResult(public let capabilities: ServerCapabilities, public let serverInfo!: ?ServerInfo = None) {}
}

@DeriveExt[Json]
public struct ClientInfo {
    @Frozen
    public ClientInfo(
        /**
         * The name of the client as defined by the client.
         */
        public let name: String,
        /**
         * The client's version as defined by the client.
         */
        public let version!: ?String = None
    ) {}
}

@DeriveExt[Json]
public struct ClientCapabilities {
    @Frozen
    public ClientCapabilities() {}
}

public enum TraceValue <: JsonSerializable & JsonDeserializable<TraceValue> {
    | Off
    | Messages
    | Verbose

    @Frozen
    public static func fromJson(r: JsonReader): TraceValue {
        if (let Some(tok) <- r.peek() && tok == JsonString) {
            return match (r.readValue<String>()) {
                case "messages" => Messages
                case "verbose" => Verbose
                case _ => Off
            }
        }

        throw IllegalStateException("unable to deserialize TraceValue")
    }

    @Frozen
    public func toJson(w: JsonWriter): Unit {
        let str = match (this) {
            case Off => "off"
            case Messages => "messages"
            case Verbose => "verbose"
        }

        w.writeValue(str)
    }
}

@DeriveExt[Json]
public struct ServerInfo {
    @Frozen
    public ServerInfo(public let name: String, public let version!: ?String = None) {}
}

@DeriveExt[Json]
public struct ServerCapabilities {
    @Frozen
    public ServerCapabilities() {}
}

@DeriveExt[Json]
public struct WorkspaceFolder {
    @Frozen
    public WorkspaceFolder(
        /**
         * The associated Uri for this workspace folder.
         */
        public let uri: Uri,
        /**
         * The name of the workspace folder. Used to refer to this
         * workspace folder in the user interface.
         */
        public let name: String) {}
}

public struct Uri <: JsonSerializable & JsonDeserializable<Uri> {
    @Frozen
    private Uri(private let inner: URL) {}

    /**
     * @throws IllegalStateException - if unable to deserialize Uri
     */
    @Frozen
    public static func fromJson(r: JsonReader): Uri {
        if (let Some(tok) <- r.peek() && tok == JsonString) {
            let inner = URL.parse(r.readValue<String>())
            return Uri(inner)
        }

        throw IllegalStateException("unable to deserialize Uri")
    }

    @Frozen
    public func toJson(w: JsonWriter): Unit {
        w.writeValue(inner.toString())
    }
}

@DeriveExt[Json]
public struct TextDocumentItem {
    @Frozen
    public TextDocumentItem(
        public let uri: Uri,
        public let languageId: String,
        public let version: Int64,
        public let text: String
    ) {}
}
