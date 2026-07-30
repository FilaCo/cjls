package cjls.lsp_types

import std.io.{InputStream, OutputStream}
import stdx.encoding.json.stream.*
import stdx.encoding.url.URL
import stdxx.deriving.*
import lsp.*

@DeriveExt[Json]
public struct ClientInfo {
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
    public ClientCapabilities() {}
}

public enum TraceValue <: JsonSerializable & JsonDeserializable<TraceValue> {
    | Off
    | Messages
    | Verbose

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

    public func toJson(w: JsonWriter): Unit {
        let str = match (this) {
            case Off => "off"
            case Messages => "messages"
            case Verbose => "verbose"
        }

        w.writeValue(str)
    }
}

/**
 * Information about the server
 *
 * @since 3.15.0
 */
@DeriveExt[Json]
public struct ServerInfo {
    public ServerInfo(
        /**
         * The name of the server as defined by the server.
         */
        public let name: String,
        /**
         * The server's version as defined by the server.
         */
        public let version!: ?String = None) {}
}

@DeriveExt[Json]
public struct ServerCapabilities {
    public ServerCapabilities() {}
}

@DeriveExt[Json]
public struct WorkspaceFolder {
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
    private Uri(private let inner: URL) {}

    /**
     * @throws IllegalStateException - if unable to deserialize Uri
     */
    public static func fromJson(r: JsonReader): Uri {
        if (let Some(tok) <- r.peek() && tok == JsonString) {
            let inner = URL.parse(r.readValue<String>())
            return Uri(inner)
        }

        throw IllegalStateException("unable to deserialize Uri")
    }

    public func toJson(w: JsonWriter): Unit {
        w.writeValue(inner.toString())
    }
}

@DeriveExt[Json]
public struct TextDocumentItem {
    public TextDocumentItem(
        public let uri: Uri,
        public let languageId: String,
        public let version: Int64,
        public let text: String
    ) {}
}
