package lsp.proto.json

import stdx.encoding.url.URL

public struct Position {
    public Position(
        /**
         * Line position in a document (zero-based).
         */
        public let line: UInt32,
        /**
         * Character offset on a line in a document (zero-based). The meaning of this
         * offset is determined by the negotiated `PositionEncodingKind`.
         *
         * If the character value is greater than the line length it defaults back
         * to the line length.
         */
        public let character: UInt32) {}
}

/**
 * A type indicating how positions are encoded,
 * specifically what column offsets mean.
 */
public enum PositionEncoding {
    /**
     * Character offsets count UTF-8 code units (e.g bytes).
     */
    Utf8
    |
        /**
         * Character offsets count UTF-16 code units.
         *
         * This is the default and must always be supported
         * by servers
         */
        Utf16
    |
        /**
         * Character offsets count UTF-32 code units.
         *
         * Implementation note: these are the same as Unicode code points,
         * so this `PositionEncoding` may also be used for an
         * encoding-agnostic representation of character offsets.
         */
        Utf32
}

public struct Range {
    public Range(
        /**
         * The range's start position.
         */
        public let start: Position,
        /**
         * The range's end position.
         */
        public let end: Position) {}
}

public enum LanguageId {
    Cangjie | Toml
}

public class TextDocumentItem {
    public TextDocumentItem(public let uri!: URL, public let languageId!: LanguageId, public let version!: Int32,
        public let text!: String) {}
}
