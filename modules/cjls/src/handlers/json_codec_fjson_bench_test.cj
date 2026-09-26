package cjls.handlers

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import stdx.encoding.json.*
import stdxx.{IntegerOrString, Nullable}
import jsonrpc.*
import fjson.*
import cjls.lsp_types.*
import cjls.lsp_types.Range as LspRange

/*
 * fjson (bench/fjson), a reader and writer of our own over bytes, for the same `lsp_types` values
 * as `JsonCodecBench`, written the way a generator would write it. One pass: `params` are decoded
 * in place when `method` came first, and are otherwise a slice of the frame — no copy — decoded
 * once the method is known. `Scalar` is the same codec scanning strings a byte at a time.
 */

func fjOnePass<P>(frame: Array<Byte>, swar: Bool, decoderFor: (String) -> (FjReader) -> P): P {
    fjOnePassOn(FjReader(frame, swar: swar), decoderFor)
}

func fjOnePassOn<P>(r: FjReader, decoderFor: (String) -> (FjReader) -> P): P {
    var version = false
    var method: ?String = None
    var params: ?P = None
    var rawParams: ?Array<Byte> = None
    r.beginObject()
    while (r.nextKey()) {
        if (r.keyIs("jsonrpc")) {
            version = r.readString() == "2.0"
        } else if (r.keyIs("method")) {
            method = r.readString()
        } else if (r.keyIs("params")) {
            match (method) {
                case Some(known) => params = decoderFor(known)(r)
                case None => rawParams = r.rawValue()
            }
        } else {
            r.skipValue()
        }
    }
    r.end()
    if (!version) {
        throw RpcException(ErrorCode.INVALID_REQUEST, "invalid \"jsonrpc\" field value")
    }
    match ((params, rawParams)) {
        case (Some(decoded), _) => decoded
        case (None, Some(raw)) =>
            r.reset(raw)
            decoderFor(method.getOrThrow())(r)
        case _ => throw RpcException(ErrorCode.INVALID_PARAMS, "no params")
    }
}

func fjPosition(r: FjReader): Position {
    var line: ?UInt32 = None
    var character: ?UInt32 = None
    r.beginObject()
    while (r.nextKey()) {
        if (r.keyIs("line")) {
            line = r.readUInt32()
        } else if (r.keyIs("character")) {
            character = r.readUInt32()
        } else {
            r.skipValue()
        }
    }
    Position(line: required(line, "line"), character: required(character, "character"))
}

func fjRange(r: FjReader): LspRange {
    var start: ?Position = None
    var end: ?Position = None
    r.beginObject()
    while (r.nextKey()) {
        if (r.keyIs("start")) {
            start = fjPosition(r)
        } else if (r.keyIs("end")) {
            end = fjPosition(r)
        } else {
            r.skipValue()
        }
    }
    LspRange(start: required(start, "start"), end: required(end, "end"))
}

func fjDidOpen(r: FjReader): DidOpenTextDocumentParams {
    var item: ?TextDocumentItem = None
    r.beginObject()
    while (r.nextKey()) {
        if (r.keyIs("textDocument")) {
            var uri: ?String = None
            var languageId: ?String = None
            var version: ?Int32 = None
            var text: ?String = None
            r.beginObject()
            while (r.nextKey()) {
                if (r.keyIs("uri")) {
                    uri = r.readString()
                } else if (r.keyIs("languageId")) {
                    languageId = r.readString()
                } else if (r.keyIs("version")) {
                    version = r.readInt32()
                } else if (r.keyIs("text")) {
                    text = r.readString()
                } else {
                    r.skipValue()
                }
            }
            item = TextDocumentItem(uri: required(uri, "uri"), languageId: LanguageKind(required(languageId, "languageId")),
                version: required(version, "version"), text: required(text, "text"))
        } else {
            r.skipValue()
        }
    }
    DidOpenTextDocumentParams(textDocument: required(item, "textDocument"))
}

/** An untagged union read by which keys are there, as a generator knowing each variant's required keys would. */
func fjContentChange(r: FjReader): TextDocumentContentChangeEvent {
    var range: ?LspRange = None
    var rangeLength: ?UInt32 = None
    var text: ?String = None
    r.beginObject()
    while (r.nextKey()) {
        if (r.keyIs("range")) {
            range = fjRange(r)
        } else if (r.keyIs("rangeLength")) {
            rangeLength = if (r.peekNull()) {
                r.readNull()
                None
            } else {
                r.readUInt32()
            }
        } else if (r.keyIs("text")) {
            text = r.readString()
        } else {
            r.skipValue()
        }
    }
    match (range) {
        case Some(range) => TextDocumentContentChangeEvent.AsTextDocumentContentChangePartial(
            TextDocumentContentChangePartial(range: range, rangeLength: rangeLength, text: required(text, "text")))
        case None => TextDocumentContentChangeEvent.AsTextDocumentContentChangeWholeDocument(
            TextDocumentContentChangeWholeDocument(text: required(text, "text")))
    }
}

func fjDidChange(r: FjReader): DidChangeTextDocumentParams {
    var document: ?VersionedTextDocumentIdentifier = None
    var changes: ?Array<TextDocumentContentChangeEvent> = None
    r.beginObject()
    while (r.nextKey()) {
        if (r.keyIs("textDocument")) {
            var uri: ?String = None
            var version: ?Int32 = None
            r.beginObject()
            while (r.nextKey()) {
                if (r.keyIs("uri")) {
                    uri = r.readString()
                } else if (r.keyIs("version")) {
                    version = r.readInt32()
                } else {
                    r.skipValue()
                }
            }
            document = VersionedTextDocumentIdentifier(uri: required(uri, "uri"), version: required(version, "version"))
        } else if (r.keyIs("contentChanges")) {
            let list = ArrayList<TextDocumentContentChangeEvent>()
            r.beginArray()
            while (r.nextItem()) {
                list.add(fjContentChange(r))
            }
            changes = list.toArray()
        } else {
            r.skipValue()
        }
    }
    DidChangeTextDocumentParams(textDocument: required(document, "textDocument"),
        contentChanges: required(changes, "contentChanges"))
}

func fjDocumentSymbolParams(r: FjReader): DocumentSymbolParams {
    var uri: ?String = None
    r.beginObject()
    while (r.nextKey()) {
        if (r.keyIs("textDocument")) {
            r.beginObject()
            while (r.nextKey()) {
                if (r.keyIs("uri")) {
                    uri = r.readString()
                } else {
                    r.skipValue()
                }
            }
        } else {
            r.skipValue()
        }
    }
    DocumentSymbolParams(textDocument: TextDocumentIdentifier(uri: required(uri, "uri")))
}

func fjWritePosition(w: FjWriter, position: Position): Unit {
    w.beginObject()
    w.name("line")
    w.uint32(position.line)
    w.name("character")
    w.uint32(position.character)
    w.endObject()
}

func fjWriteRange(w: FjWriter, range: LspRange): Unit {
    w.beginObject()
    w.name("start")
    fjWritePosition(w, range.start)
    w.name("end")
    fjWritePosition(w, range.end)
    w.endObject()
}

func fjWriteSymbol(w: FjWriter, symbol: DocumentSymbol): Unit {
    w.beginObject()
    w.name("name")
    w.string(symbol.name)
    if (let Some(detail) <- symbol.detail) {
        w.name("detail")
        w.string(detail)
    }
    w.name("kind")
    w.int64(symbolKindValue(symbol.kind))
    w.name("range")
    fjWriteRange(w, symbol.range)
    w.name("selectionRange")
    fjWriteRange(w, symbol.selectionRange)
    if (let Some(children) <- symbol.children) {
        w.name("children")
        w.beginArray()
        for (child in children) {
            fjWriteSymbol(w, child)
        }
        w.endArray()
    }
    w.endObject()
}

func fjResponse(id: Int64, symbols: Array<DocumentSymbol>, swar: Bool): Array<Byte> {
    fjResponseInto(FjWriter(swar: swar), id, symbols)
}

func fjResponseInto(w: FjWriter, id: Int64, symbols: Array<DocumentSymbol>): Array<Byte> {
    w.beginObject()
    w.name("jsonrpc")
    w.string("2.0")
    w.name("id")
    w.int64(id)
    w.name("result")
    w.beginArray()
    for (symbol in symbols) {
        fjWriteSymbol(w, symbol)
    }
    w.endArray()
    w.endObject()
    w.bytes()
}

func fjDidOpenDecoder(_: String): (FjReader) -> DidOpenTextDocumentParams {
    fjDidOpen
}

func fjDidChangeDecoder(_: String): (FjReader) -> DidChangeTextDocumentParams {
    fjDidChange
}

func fjDocumentSymbolDecoder(_: String): (FjReader) -> DocumentSymbolParams {
    fjDocumentSymbolParams
}

/** The did-open frame with `params` before `method`, which takes the slice path. */
let DID_OPEN_PARAMS_FIRST_FRAME = {
    =>
    let w = FjWriter()
    w.beginObject()
    w.name("params")
    w.raw(streamEnvelope(DID_OPEN_FRAME).params.getOrThrow())
    w.name("method")
    w.string(DidOpenTextDocumentNotificationSpec.METHOD)
    w.name("jsonrpc")
    w.string("2.0")
    w.endObject()
    w.bytes()
}()

@Test
class JsonCodecFjsonTest {
    @TestCase
    func fjsonReadsWhatTheServerReads() {
        for (swar in [true, false]) {
            // act
            let open = fjOnePass(DID_OPEN_FRAME, swar, fjDidOpenDecoder)
            let paramsFirst = fjOnePass(DID_OPEN_PARAMS_FIRST_FRAME, swar, fjDidOpenDecoder)
            let current = DidOpenTextDocumentNotificationSpec().decodeParams(currentParams(DID_OPEN_FRAME))
            let full = fjOnePass(DID_CHANGE_FULL_FRAME, swar, fjDidChangeDecoder)
            let key = fjOnePass(DID_CHANGE_KEY_FRAME, swar, fjDidChangeDecoder)
            let currentKey = DidChangeTextDocumentNotificationSpec().decodeParams(currentParams(DID_CHANGE_KEY_FRAME))

            // assert
            @Expect(open.textDocument.text, current.textDocument.text)
            @Expect(open.textDocument.text, BENCH_TEXT)
            @Expect(open.textDocument.uri, current.textDocument.uri)
            @Expect(open.textDocument.version, current.textDocument.version)
            @Expect(open.textDocument.languageId.value, current.textDocument.languageId.value)
            @Expect(paramsFirst.textDocument.text, BENCH_TEXT)
            match (full.contentChanges[0]) {
                case TextDocumentContentChangeEvent.AsTextDocumentContentChangeWholeDocument(change) =>
                    @Expect(change.text, BENCH_TEXT)
                case _ => @Fail("a whole-document change was read as a partial one")
            }
            match ((key.contentChanges[0], currentKey.contentChanges[0])) {
                case (TextDocumentContentChangeEvent.AsTextDocumentContentChangePartial(s),
                    TextDocumentContentChangeEvent.AsTextDocumentContentChangePartial(c)) =>
                    @Expect(s.text, c.text)
                    @Expect(s.range.start.line, c.range.start.line)
                    @Expect(s.range.end.character, c.range.end.character)
                case _ => @Fail("a partial change was read as a whole-document one")
            }
            @Expect(fjOnePass(DOCUMENT_SYMBOL_FRAME, swar, fjDocumentSymbolDecoder).textDocument.uri, BENCH_URI)
        }
    }

    @TestCase
    func fjsonWritesTheServersResponseByteForByte() {
        // arrange
        let current = currentResponse(7, BENCH_RESULT)

        for (swar in [true, false]) {
            // act
            let written = fjResponse(7, BENCH_SYMBOLS, swar)

            // assert
            @Expect(JsonValue.fromStr(String.fromUtf8(written)).toString(), JsonValue.fromStr(String.fromUtf8(current)).toString())
        }
    }
}

@Test
@Configure[warmup: 1 * Duration.second, minDuration: 3 * Duration.second]
class JsonCodecFjsonBench {
    @Bench
    func didOpen64KbFjson(): Unit {
        benchSink += Int64(fjOnePass(DID_OPEN_FRAME, false, fjDidOpenDecoder).textDocument.version)
    }

    @Bench
    func didOpen64KbFjsonSwar(): Unit {
        benchSink += Int64(fjOnePass(DID_OPEN_FRAME, true, fjDidOpenDecoder).textDocument.version)
    }

    @Bench
    func didOpen64KbFjsonParamsFirst(): Unit {
        benchSink += Int64(fjOnePass(DID_OPEN_PARAMS_FIRST_FRAME, false, fjDidOpenDecoder).textDocument.version)
    }

    @Bench
    func didChangeFull64KbFjson(): Unit {
        benchSink += Int64(fjOnePass(DID_CHANGE_FULL_FRAME, false, fjDidChangeDecoder).textDocument.version)
    }

    @Bench
    func didChangeKeystrokeFjson(): Unit {
        benchSink += Int64(fjOnePass(DID_CHANGE_KEY_FRAME, false, fjDidChangeDecoder).textDocument.version)
    }

    @Bench
    func documentSymbolRequestFjson(): Unit {
        benchSink += fjOnePass(DOCUMENT_SYMBOL_FRAME, false, fjDocumentSymbolDecoder).textDocument.uri.size
    }

    @Bench
    func documentSymbolResponse550Fjson(): Unit {
        benchSink += fjResponse(7, BENCH_SYMBOLS, false).size
    }

    @Bench
    func documentSymbolResponse550FjsonSwar(): Unit {
        benchSink += fjResponse(7, BENCH_SYMBOLS, true).size
    }
}

/** A connection's reader and writer, kept from one message to the next. */
let FJ_READER = FjReader(Array<Byte>())
let FJ_WRITER = FjWriter()

func fjReused<P>(frame: Array<Byte>, decoderFor: (String) -> (FjReader) -> P): P {
    FJ_READER.reset(frame)
    fjOnePassOn(FJ_READER, decoderFor)
}

func fjResponseReused(id: Int64, symbols: Array<DocumentSymbol>): Int64 {
    FJ_WRITER.clear()
    fjResponseInto(FJ_WRITER, id, symbols).size
}

@Test
@Configure[warmup: 1 * Duration.second, minDuration: 3 * Duration.second]
class JsonCodecFjsonReusedBench {
    @Bench
    func didOpen64KbFjsonReused(): Unit {
        benchSink += Int64(fjReused(DID_OPEN_FRAME, fjDidOpenDecoder).textDocument.version)
    }

    @Bench
    func didChangeKeystrokeFjsonReused(): Unit {
        benchSink += Int64(fjReused(DID_CHANGE_KEY_FRAME, fjDidChangeDecoder).textDocument.version)
    }

    @Bench
    func documentSymbolResponse550FjsonReused(): Unit {
        benchSink += fjResponseReused(7, BENCH_SYMBOLS)
    }
}

@Test
@Measure[Runtime(AllocatedMemory)]
@Configure[warmup: 100, minDuration: 1 * Duration.second]
class JsonCodecFjsonReusedAllocationBench {
    @Bench
    func didOpen64KbFjsonReused(): Unit {
        benchSink += Int64(fjReused(DID_OPEN_FRAME, fjDidOpenDecoder).textDocument.version)
    }

    @Bench
    func didChangeKeystrokeFjsonReused(): Unit {
        benchSink += Int64(fjReused(DID_CHANGE_KEY_FRAME, fjDidChangeDecoder).textDocument.version)
    }

    @Bench
    func documentSymbolResponse550FjsonReused(): Unit {
        benchSink += fjResponseReused(7, BENCH_SYMBOLS)
    }
}

@Test
@Measure[Runtime(AllocatedMemory)]
@Configure[warmup: 100, minDuration: 1 * Duration.second]
class JsonCodecFjsonAllocationBench {
    @Bench
    func didOpen64KbFjson(): Unit {
        benchSink += Int64(fjOnePass(DID_OPEN_FRAME, false, fjDidOpenDecoder).textDocument.version)
    }

    @Bench
    func didChangeKeystrokeFjson(): Unit {
        benchSink += Int64(fjOnePass(DID_CHANGE_KEY_FRAME, false, fjDidChangeDecoder).textDocument.version)
    }

    @Bench
    func documentSymbolResponse550Fjson(): Unit {
        benchSink += fjResponse(7, BENCH_SYMBOLS, false).size
    }
}
