package cjls.handlers

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import stdx.encoding.json.*
import CJson.*
import CJson.jsonmacro.*
import cjls.lsp_types.*
import cjls.lsp_types.Range as LspRange

/*
 * CJson (gitcode.com/Cangjie-TPC/CJson), the same messages as `JsonCodecBench`. Written for cjc
 * 0.55 against the `encoding.json` of the old std: vendored with `stdx.encoding.json` and the
 * collections' `add` in place of `put`/`append`, nothing else. `@JsonSerializable` wants `var`
 * fields with defaults, a constructor without parameters, `Option<T>` spelled out, `ArrayList`
 * rather than `Array`, and knows no unsigned integers (`Int64` here, the same on the wire). It
 * writes `None` as `null` with no way to omit the key, so its response is not what the server
 * sends, and its reader gives `""` or `0` for a value of the wrong type rather than failing.
 */

@JsonSerializable
public struct CxPosition {
    public var line: Int64 = 0
    public var character: Int64 = 0
}

@JsonSerializable
public struct CxRange {
    public var start: CxPosition = CxPosition()
    public var end: CxPosition = CxPosition()
}

@JsonSerializable
public struct CxTextDocumentItem {
    public var uri: String = ""
    public var languageId: String = ""
    public var version: Int32 = 0
    public var text: String = ""
}

@JsonSerializable
public struct CxDidOpenParams {
    public var textDocument: CxTextDocumentItem = CxTextDocumentItem()
}

@JsonSerializable
public struct CxVersionedDocument {
    public var uri: String = ""
    public var version: Int32 = 0
}

@JsonSerializable
public struct CxContentChange {
    public var range: Option<CxRange> = None
    public var rangeLength: Option<Int64> = None
    public var text: String = ""
}

@JsonSerializable
public struct CxDidChangeParams {
    public var textDocument: CxVersionedDocument = CxVersionedDocument()
    public var contentChanges: ArrayList<CxContentChange> = ArrayList<CxContentChange>()
}

@JsonSerializable
public struct CxDocumentIdentifier {
    public var uri: String = ""
}

@JsonSerializable
public struct CxDocumentSymbolParams {
    public var textDocument: CxDocumentIdentifier = CxDocumentIdentifier()
}

@JsonSerializable
public class CxDocumentSymbol {
    public var name: String = ""
    public var detail: Option<String> = None
    public var kind: Int64 = 0
    public var range: CxRange = CxRange()
    public var selectionRange: CxRange = CxRange()
    public var children: Option<ArrayList<CxDocumentSymbol>> = None
}

func cxParams(frame: Array<Byte>): JsonValue {
    let envelope = JsonValue.fromStr(String.fromUtf8(frame)).asObject()
    if (envelope.get("jsonrpc").flatMap {v => (v as JsonString)}.map {v => v.getValue()} != Some("2.0")) {
        throw IllegalArgumentException("invalid \"jsonrpc\" field value")
    }
    envelope.get("method").getOrThrow()
    envelope.get("params").getOrThrow()
}

func cxPosition(position: Position): CxPosition {
    var p = CxPosition()
    p.line = Int64(position.line)
    p.character = Int64(position.character)
    p
}

func cxRange(range: LspRange): CxRange {
    var r = CxRange()
    r.start = cxPosition(range.start)
    r.end = cxPosition(range.end)
    r
}

func cxSymbol(symbol: DocumentSymbol): CxDocumentSymbol {
    let s = CxDocumentSymbol()
    s.name = symbol.name
    s.detail = symbol.detail
    s.kind = symbolKindValue(symbol.kind)
    s.range = cxRange(symbol.range)
    s.selectionRange = cxRange(symbol.selectionRange)
    s.children = symbol.children.map {children => ArrayList<CxDocumentSymbol>(children.map(cxSymbol))}
    s
}

let CX_SYMBOLS = ArrayList<CxDocumentSymbol>(BENCH_SYMBOLS.map(cxSymbol))

func cxResponse(id: Int64, symbols: ArrayList<CxDocumentSymbol>): Array<Byte> {
    let body = JsonObject()
    body.put("jsonrpc", JsonString("2.0"))
    body.put("id", JsonInt(id))
    body.put("result", symbols.toJsonValue())
    body.toString().toArray()
}

@Test
class JsonCodecCJsonTest {
    @TestCase
    func cjsonReadsWhatTheServerReads() {
        // act
        let open = CxDidOpenParams.fromJsonValue(cxParams(DID_OPEN_FRAME))
        let full = CxDidChangeParams.fromJsonValue(cxParams(DID_CHANGE_FULL_FRAME))
        let key = CxDidChangeParams.fromJsonValue(cxParams(DID_CHANGE_KEY_FRAME))
        let symbol = CxDocumentSymbolParams.fromJsonValue(cxParams(DOCUMENT_SYMBOL_FRAME))

        // assert
        @Expect(open.textDocument.text, BENCH_TEXT)
        @Expect(open.textDocument.uri, BENCH_URI)
        @Expect(full.contentChanges[0].text, BENCH_TEXT)
        @Expect(full.contentChanges[0].range.isNone())
        @Expect(key.contentChanges[0].range.map {r => r.start.line}, Some(120))
        @Expect(key.contentChanges[0].text, "x")
        @Expect(symbol.textDocument.uri, BENCH_URI)
    }

    @TestCase
    func cjsonWritesTheServersResponseWithNullsForWhatIsAbsent() {
        // act
        let written = JsonValue.fromStr(String.fromUtf8(cxResponse(7, CX_SYMBOLS))).asObject()
        let first = written.get("result").getOrThrow().asArray()[0].asObject()

        // assert
        @Expect(written.get("result").getOrThrow().asArray().size(), 50)
        @Expect(first.get("detail").getOrThrow() is JsonNull)
        @Expect(first.get("children").getOrThrow().asArray().size(), 10)
    }
}

@Test
@Configure[warmup: 1 * Duration.second, minDuration: 3 * Duration.second]
class JsonCodecCJsonBench {
    @Bench
    func didOpen64KbCJson(): Unit {
        benchSink += Int64(CxDidOpenParams.fromJsonValue(cxParams(DID_OPEN_FRAME)).textDocument.version)
    }

    @Bench
    func didChangeFull64KbCJson(): Unit {
        benchSink += Int64(CxDidChangeParams.fromJsonValue(cxParams(DID_CHANGE_FULL_FRAME)).textDocument.version)
    }

    @Bench
    func didChangeKeystrokeCJson(): Unit {
        benchSink += Int64(CxDidChangeParams.fromJsonValue(cxParams(DID_CHANGE_KEY_FRAME)).textDocument.version)
    }

    @Bench
    func documentSymbolRequestCJson(): Unit {
        benchSink += CxDocumentSymbolParams.fromJsonValue(cxParams(DOCUMENT_SYMBOL_FRAME)).textDocument.uri.size
    }

    @Bench
    func documentSymbolResponse550CJson(): Unit {
        benchSink += cxResponse(7, CX_SYMBOLS).size
    }
}

@Test
@Measure[Runtime(AllocatedMemory)]
@Configure[warmup: 100, minDuration: 1 * Duration.second]
class JsonCodecCJsonAllocationBench {
    @Bench
    func didOpen64KbCJson(): Unit {
        benchSink += Int64(CxDidOpenParams.fromJsonValue(cxParams(DID_OPEN_FRAME)).textDocument.version)
    }

    @Bench
    func didChangeKeystrokeCJson(): Unit {
        benchSink += Int64(CxDidChangeParams.fromJsonValue(cxParams(DID_CHANGE_KEY_FRAME)).textDocument.version)
    }

    @Bench
    func documentSymbolResponse550CJson(): Unit {
        benchSink += cxResponse(7, CX_SYMBOLS).size
    }
}
