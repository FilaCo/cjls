package cjls.handlers

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cjjson.*
import cjjson.macros.*
import cjls.lsp_types.*
import cjls.lsp_types.Range as LspRange

/*
 * cangjieJSON (gitcode.com/Cangjie-TPC/cangjieJSON), the same messages as `JsonCodecBench`. Its
 * `@JsonAdapter` wants `var` fields with defaults and a constructor without parameters, and does
 * not take an `enum`: the content change, an untagged union in `lsp_types`, is one struct with an
 * optional `range`, as a user of the library would write it. It reads through `JsonValue` and
 * writes through it, so the envelope is a `JsonObject` and `params` is read from it once `method`
 * is known.
 */

@JsonAdapter
public struct CjPosition {
    public var line: UInt32 = 0
    public var character: UInt32 = 0
}

@JsonAdapter
public struct CjRange {
    public var start: CjPosition = CjPosition()
    public var end: CjPosition = CjPosition()
}

@JsonAdapter
public struct CjTextDocumentItem {
    public var uri: String = ""
    public var languageId: String = ""
    public var version: Int32 = 0
    public var text: String = ""
}

@JsonAdapter
public struct CjDidOpenParams {
    public var textDocument: CjTextDocumentItem = CjTextDocumentItem()
}

@JsonAdapter
public struct CjVersionedDocument {
    public var uri: String = ""
    public var version: Int32 = 0
}

@JsonAdapter
public struct CjContentChange {
    @JsonIgnoreNull
    public var range: ?CjRange = None
    @JsonIgnoreNull
    public var rangeLength: ?UInt32 = None
    public var text: String = ""
}

@JsonAdapter
public struct CjDidChangeParams {
    public var textDocument: CjVersionedDocument = CjVersionedDocument()
    public var contentChanges: Array<CjContentChange> = []
}

@JsonAdapter
public struct CjDocumentIdentifier {
    public var uri: String = ""
}

@JsonAdapter
public struct CjDocumentSymbolParams {
    public var textDocument: CjDocumentIdentifier = CjDocumentIdentifier()
}

@JsonAdapter
public class CjDocumentSymbol {
    public var name: String = ""
    @JsonIgnoreNull
    public var detail: ?String = None
    public var kind: Int64 = 0
    public var range: CjRange = CjRange()
    public var selectionRange: CjRange = CjRange()
    @JsonIgnoreNull
    public var children: ?Array<CjDocumentSymbol> = None
}

func cjParams(frame: Array<Byte>): JsonValue {
    let envelope = JsonValue.fromStr(String.fromUtf8(frame)).asObject()
    if (envelope.get("jsonrpc").flatMap {v => (v as JsonString)}.map {v => v.getValue()} != Some("2.0")) {
        throw IllegalArgumentException("invalid \"jsonrpc\" field value")
    }
    envelope.get("method").getOrThrow()
    envelope.get("params").getOrThrow()
}

func cjRange(range: LspRange): CjRange {
    var r = CjRange()
    r.start = CjPosition()
    r.start.line = range.start.line
    r.start.character = range.start.character
    r.end = CjPosition()
    r.end.line = range.end.line
    r.end.character = range.end.character
    r
}

func cjSymbol(symbol: DocumentSymbol): CjDocumentSymbol {
    let s = CjDocumentSymbol()
    s.name = symbol.name
    s.detail = symbol.detail
    s.kind = symbolKindValue(symbol.kind)
    s.range = cjRange(symbol.range)
    s.selectionRange = cjRange(symbol.selectionRange)
    s.children = symbol.children.map {children => children.map(cjSymbol)}
    s
}

let CJ_SYMBOLS = BENCH_SYMBOLS.map(cjSymbol)

func cjResponse(id: Int64, symbols: Array<CjDocumentSymbol>): Array<Byte> {
    let body = JsonObject()
    body.put("jsonrpc", JsonString("2.0"))
    body.put("id", JsonInt(id))
    body.put("result", symbols.toJsonValue())
    body.toString().toArray()
}

@Test
class JsonCodecCangjieJsonTest {
    @TestCase
    func cangjieJsonReadsWhatTheServerReads() {
        // act
        let open = CjDidOpenParams.fromJsonValue(cjParams(DID_OPEN_FRAME))
        let full = CjDidChangeParams.fromJsonValue(cjParams(DID_CHANGE_FULL_FRAME))
        let key = CjDidChangeParams.fromJsonValue(cjParams(DID_CHANGE_KEY_FRAME))
        let symbol = CjDocumentSymbolParams.fromJsonValue(cjParams(DOCUMENT_SYMBOL_FRAME))

        // assert
        @Expect(open.textDocument.text, BENCH_TEXT)
        @Expect(open.textDocument.uri, BENCH_URI)
        @Expect(full.contentChanges[0].text, BENCH_TEXT)
        @Expect(full.contentChanges[0].range.isNone())
        @Expect(key.contentChanges[0].range.map {r => r.start.line}, Some(UInt32(120)))
        @Expect(key.contentChanges[0].text, "x")
        @Expect(symbol.textDocument.uri, BENCH_URI)
    }

    @TestCase
    func cangjieJsonWritesTheSameResponseAsTheServer() {
        // act
        let current = String.fromUtf8(currentResponse(7, BENCH_RESULT))
        let written = String.fromUtf8(cjResponse(7, CJ_SYMBOLS))

        // assert
        @Expect(JsonValue.fromStr(written).toString(), JsonValue.fromStr(current).toString())
    }
}

@Test
@Configure[warmup: 1 * Duration.second, minDuration: 3 * Duration.second]
class JsonCodecCangjieJsonBench {
    @Bench
    func didOpen64KbCangjieJson(): Unit {
        benchSink += Int64(CjDidOpenParams.fromJsonValue(cjParams(DID_OPEN_FRAME)).textDocument.version)
    }

    @Bench
    func didChangeFull64KbCangjieJson(): Unit {
        benchSink += Int64(CjDidChangeParams.fromJsonValue(cjParams(DID_CHANGE_FULL_FRAME)).textDocument.version)
    }

    @Bench
    func didChangeKeystrokeCangjieJson(): Unit {
        benchSink += Int64(CjDidChangeParams.fromJsonValue(cjParams(DID_CHANGE_KEY_FRAME)).textDocument.version)
    }

    @Bench
    func documentSymbolRequestCangjieJson(): Unit {
        benchSink += CjDocumentSymbolParams.fromJsonValue(cjParams(DOCUMENT_SYMBOL_FRAME)).textDocument.uri.size
    }

    @Bench
    func documentSymbolResponse550CangjieJson(): Unit {
        benchSink += cjResponse(7, CJ_SYMBOLS).size
    }
}

@Test
@Measure[Runtime(AllocatedMemory)]
@Configure[warmup: 100, minDuration: 1 * Duration.second]
class JsonCodecCangjieJsonAllocationBench {
    @Bench
    func didOpen64KbCangjieJson(): Unit {
        benchSink += Int64(CjDidOpenParams.fromJsonValue(cjParams(DID_OPEN_FRAME)).textDocument.version)
    }

    @Bench
    func didChangeKeystrokeCangjieJson(): Unit {
        benchSink += Int64(CjDidChangeParams.fromJsonValue(cjParams(DID_CHANGE_KEY_FRAME)).textDocument.version)
    }

    @Bench
    func documentSymbolResponse550CangjieJson(): Unit {
        benchSink += cjResponse(7, CJ_SYMBOLS).size
    }
}
