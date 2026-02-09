package lsp.proto.json

import stdx.encoding.json.stream.*

public struct InitializeParams <: JsonSerializable & JsonDeserializable<InitializeParams> {
    public InitializeParams(
        /**
         * The process Id of the parent process that started the server. Is None if
         * the process has not been started by another process. If the parent
         * process is not alive then the server should exit (see exit notification)
         * its process.
         */
        public let processId: ?Int32) {}

    public static func fromJson(r: JsonReader): InitializeParams {
        throw Exception()
    }

    public func toJson(w: JsonWriter): Unit {}
}
