package cjls.handlers

import std.collection.*
import std.io.*
import std.unittest.*
import std.unittest.testmacro.*
import stdx.encoding.json.*
import stdx.encoding.json.stream.*
import stdx.serialization.serialization.*
import stdxx.{IntegerOrString, Nullable}
import jsonrpc.*
import cjls.lsp_types.*
import cjls.lsp_types.Range as LspRange

/*
 * The codec the server has — bytes, `String`, `JsonValue`, `DataModel`, `Body`, the params type —
 * against `stdx.encoding.json.stream`, which reads bytes into the params type and writes a result
 * into bytes with no tree between. The stream side is written by hand for the messages measured,
 * the way a generator would write it; the envelope keeps `params` as raw bytes until the method
 * says what they are, since `params` may come before `method`.
 *
 * `cjpm bench -m modules/cjls --filter 'JsonCodec*'`
 */

let BENCH_URI = "file:///home/user/project/src/main.cj"

/** Code with what a real file has for JSON to escape: quotes, backslashes, tabs, non-ASCII. */
func benchSource(bytes: Int64): String {
    let line = "    let greeting = \"héllo, \\\"мир\\\"\\t\" // a comment 😀\n"
    let sb = StringBuilder()
    while (sb.size < bytes) {
        sb.append(line)
    }
    sb.toString()
}

func notificationFrame(method: String, params: DataModel): Array<Byte> {
    NotificationBody(method, params: ArrayOrObject.deserialize(params)).enveloped().serialize().toJson().toString().toArray()
}

func requestFrame(id: Int32, method: String, params: DataModel): Array<Byte> {
    RequestBody(IntegerOrString.Integer(id), method, params: ArrayOrObject.deserialize(params))
        .enveloped()
        .serialize()
        .toJson()
        .toString()
        .toArray()
}

func benchPartialChange(line: UInt32, text: String): TextDocumentContentChangeEvent {
    TextDocumentContentChangeEvent.AsTextDocumentContentChangePartial(TextDocumentContentChangePartial(
        range: LspRange(start: Position(line: line, character: 8), end: Position(line: line, character: 8)), text: text))
}

func benchWholeChange(text: String): TextDocumentContentChangeEvent {
    TextDocumentContentChangeEvent.AsTextDocumentContentChangeWholeDocument(
        TextDocumentContentChangeWholeDocument(text: text))
}

/** 50 classes of 10 methods: an outline of a large file. */
func benchSymbols(): Array<DocumentSymbol> {
    func range(line: UInt32, lines: UInt32): LspRange {
        LspRange(start: Position(line: line, character: 4), end: Position(line: line + lines, character: 5))
    }
    Array<DocumentSymbol>(50) {
        c =>
        let classLine = UInt32(c * 100)
        let methods = Array<DocumentSymbol>(10) {
            m =>
            let line = classLine + UInt32(m * 9 + 1)
            DocumentSymbol(name: "method${m}OfClass${c}", detail: "(a: Int64, b: String): Unit", kind: SymbolKind.Method,
                range: range(line, 8), selectionRange: range(line, 0))
        }
        DocumentSymbol(name: "Class${c}", kind: SymbolKind.Class, range: range(classLine, 99),
            selectionRange: range(classLine, 0), children: methods)
    }
}

let BENCH_TEXT = benchSource(64 * 1024)

let DID_OPEN_FRAME = notificationFrame(DidOpenTextDocumentNotificationSpec.METHOD,
    DidOpenTextDocumentParams(
        textDocument: TextDocumentItem(uri: BENCH_URI, languageId: LanguageKind("cangjie"), version: 1, text: BENCH_TEXT))
        .serialize())

let DID_CHANGE_FULL_FRAME = notificationFrame(DidChangeTextDocumentNotificationSpec.METHOD,
    DidChangeTextDocumentParams(textDocument: VersionedTextDocumentIdentifier(uri: BENCH_URI, version: 2),
        contentChanges: [benchWholeChange(BENCH_TEXT)]).serialize())

let DID_CHANGE_KEY_FRAME = notificationFrame(DidChangeTextDocumentNotificationSpec.METHOD,
    DidChangeTextDocumentParams(textDocument: VersionedTextDocumentIdentifier(uri: BENCH_URI, version: 3),
        contentChanges: [benchPartialChange(120, "x")]).serialize())

let DOCUMENT_SYMBOL_FRAME = requestFrame(7, DocumentSymbolRequestSpec.METHOD,
    DocumentSymbolParams(textDocument: TextDocumentIdentifier(uri: BENCH_URI)).serialize())

let BENCH_SYMBOLS = benchSymbols()

let BENCH_RESULT = Nullable<SymbolInformationsOrDocumentSymbols>.Value(
    SymbolInformationsOrDocumentSymbols.AsDocumentSymbols(BENCH_SYMBOLS))

// ---- the codec the server has ----

func currentParams(frame: Array<Byte>): ?ArrayOrObject {
    let jv = JsonValue.fromStr(String.fromUtf8(frame))
    match (Body.deserialize(DataModel.fromJson(jv))) {
        case Body.Notification(note) => note.params
        case Body.Request(req) => req.params
        case Body.Response(_) => throw IllegalStateException("a response")
    }
}

func currentResponse(id: Int32, result: Nullable<SymbolInformationsOrDocumentSymbols>): Array<Byte> {
    let dm = DocumentSymbolRequestSpec().encodeResult(result)
    ResponseBody(Nullable.Value(IntegerOrString.Integer(id)), ResultOrError.Result(dm))
        .enveloped()
        .serialize()
        .toJson()
        .toString()
        .toArray()
}

// ---- the stream codec ----

struct RawMessage {
    RawMessage(let method: String, let id: ?IntegerOrString, let params: ?Array<Byte>) {}
}

func streamReader(bytes: Array<Byte>): JsonReader {
    let buffer = ByteBuffer()
    buffer.write(bytes)
    JsonReader(buffer)
}

func isObjectEnd(r: JsonReader): Bool {
    r.peek() == Some(JsonToken.EndObject)
}

func streamEnvelope(frame: Array<Byte>): RawMessage {
    let r = streamReader(frame)
    var version: ?String = None
    var method: ?String = None
    var id: ?IntegerOrString = None
    var params: ?Array<Byte> = None
    r.startObject()
    while (!isObjectEnd(r)) {
        match (r.readName()) {
            case "jsonrpc" => version = r.readValue<String>()
            case "method" => method = r.readValue<String>()
            case "id" => id = match (r.peek()) {
                case Some(JsonToken.JsonString) => IntegerOrString.String(r.readValue<String>())
                case _ => IntegerOrString.Integer(r.readValue<Int32>())
            }
            case "params" => params = r.readValueBytes()
            case _ => r.skip()
        }
    }
    r.endObject()
    if (version != Some("2.0")) {
        throw RpcException(ErrorCode.INVALID_REQUEST, "invalid \"jsonrpc\" field value")
    }
    RawMessage(method.getOrThrow(), id, params)
}

/**
 * One pass when `method` comes before `params`, as every client writes it: the params are read
 * in place by the decoder the method picks. Only the other order pays for `readValueBytes`.
 */
func streamOnePass<P>(frame: Array<Byte>, decoderFor: (String) -> (JsonReader) -> P): P {
    let r = streamReader(frame)
    var version: ?String = None
    var method: ?String = None
    var params: ?P = None
    var rawParams: ?Array<Byte> = None
    r.startObject()
    while (!isObjectEnd(r)) {
        match (r.readName()) {
            case "jsonrpc" => version = r.readValue<String>()
            case "method" => method = r.readValue<String>()
            case "params" => match (method) {
                case Some(known) => params = decoderFor(known)(r)
                case None => rawParams = r.readValueBytes()
            }
            case _ => r.skip()
        }
    }
    r.endObject()
    if (version != Some("2.0")) {
        throw RpcException(ErrorCode.INVALID_REQUEST, "invalid \"jsonrpc\" field value")
    }
    match ((params, rawParams)) {
        case (Some(decoded), _) => decoded
        case (None, Some(raw)) => decoderFor(method.getOrThrow())(streamReader(raw))
        case _ => throw RpcException(ErrorCode.INVALID_PARAMS, "no params")
    }
}

func required<T>(value: ?T, name: String): T {
    value ?? throw RpcException(ErrorCode.INVALID_PARAMS, "missing field `${name}`")
}

func streamPosition(r: JsonReader): Position {
    var line: ?UInt32 = None
    var character: ?UInt32 = None
    r.startObject()
    while (!isObjectEnd(r)) {
        match (r.readName()) {
            case "line" => line = r.readValue<UInt32>()
            case "character" => character = r.readValue<UInt32>()
            case _ => r.skip()
        }
    }
    r.endObject()
    Position(line: required(line, "line"), character: required(character, "character"))
}

func streamRange(r: JsonReader): LspRange {
    var start: ?Position = None
    var end: ?Position = None
    r.startObject()
    while (!isObjectEnd(r)) {
        match (r.readName()) {
            case "start" => start = streamPosition(r)
            case "end" => end = streamPosition(r)
            case _ => r.skip()
        }
    }
    r.endObject()
    LspRange(start: required(start, "start"), end: required(end, "end"))
}

func streamDidOpen(r: JsonReader): DidOpenTextDocumentParams {
    var item: ?TextDocumentItem = None
    r.startObject()
    while (!isObjectEnd(r)) {
        match (r.readName()) {
            case "textDocument" =>
                var uri: ?String = None
                var languageId: ?String = None
                var version: ?Int32 = None
                var text: ?String = None
                r.startObject()
                while (!isObjectEnd(r)) {
                    match (r.readName()) {
                        case "uri" => uri = r.readValue<String>()
                        case "languageId" => languageId = r.readValue<String>()
                        case "version" => version = r.readValue<Int32>()
                        case "text" => text = r.readValue<String>()
                        case _ => r.skip()
                    }
                }
                r.endObject()
                item = TextDocumentItem(uri: required(uri, "uri"),
                    languageId: LanguageKind(required(languageId, "languageId")),
                    version: required(version, "version"), text: required(text, "text"))
            case _ => r.skip()
        }
    }
    r.endObject()
    DidOpenTextDocumentParams(textDocument: required(item, "textDocument"))
}

/** An untagged union read by which keys are there, not by trying each variant in turn. */
func streamContentChange(r: JsonReader): TextDocumentContentChangeEvent {
    var range: ?LspRange = None
    var rangeLength: ?UInt32 = None
    var text: ?String = None
    r.startObject()
    while (!isObjectEnd(r)) {
        match (r.readName()) {
            case "range" => range = streamRange(r)
            case "rangeLength" => rangeLength = r.readValue<?UInt32>()
            case "text" => text = r.readValue<String>()
            case _ => r.skip()
        }
    }
    r.endObject()
    match (range) {
        case Some(range) => TextDocumentContentChangeEvent.AsTextDocumentContentChangePartial(
            TextDocumentContentChangePartial(range: range, rangeLength: rangeLength, text: required(text, "text")))
        case None => TextDocumentContentChangeEvent.AsTextDocumentContentChangeWholeDocument(
            TextDocumentContentChangeWholeDocument(text: required(text, "text")))
    }
}

func streamDidChange(r: JsonReader): DidChangeTextDocumentParams {
    var document: ?VersionedTextDocumentIdentifier = None
    var changes: ?Array<TextDocumentContentChangeEvent> = None
    r.startObject()
    while (!isObjectEnd(r)) {
        match (r.readName()) {
            case "textDocument" =>
                var uri: ?String = None
                var version: ?Int32 = None
                r.startObject()
                while (!isObjectEnd(r)) {
                    match (r.readName()) {
                        case "uri" => uri = r.readValue<String>()
                        case "version" => version = r.readValue<Int32>()
                        case _ => r.skip()
                    }
                }
                r.endObject()
                document = VersionedTextDocumentIdentifier(uri: required(uri, "uri"),
                    version: required(version, "version"))
            case "contentChanges" =>
                let list = ArrayList<TextDocumentContentChangeEvent>()
                r.startArray()
                while (r.peek() != Some(JsonToken.EndArray)) {
                    list.add(streamContentChange(r))
                }
                r.endArray()
                changes = list.toArray()
            case _ => r.skip()
        }
    }
    r.endObject()
    DidChangeTextDocumentParams(textDocument: required(document, "textDocument"),
        contentChanges: required(changes, "contentChanges"))
}

func streamDocumentSymbolParams(r: JsonReader): DocumentSymbolParams {
    var uri: ?String = None
    r.startObject()
    while (!isObjectEnd(r)) {
        match (r.readName()) {
            case "textDocument" =>
                r.startObject()
                while (!isObjectEnd(r)) {
                    match (r.readName()) {
                        case "uri" => uri = r.readValue<String>()
                        case _ => r.skip()
                    }
                }
                r.endObject()
            case _ => r.skip()
        }
    }
    r.endObject()
    DocumentSymbolParams(textDocument: TextDocumentIdentifier(uri: required(uri, "uri")))
}

func symbolKindValue(kind: SymbolKind): Int64 {
    match (kind) {
        case SymbolKind.Class => 5
        case SymbolKind.Method => 6
        case SymbolKind.Function => 12
        case _ => (kind.serialize() as DataModelInt).getOrThrow().getValue()
    }
}

func streamWritePosition(w: JsonWriter, position: Position): Unit {
    w.startObject()
    w.writeName("line").writeValue(position.line)
    w.writeName("character").writeValue(position.character)
    w.endObject()
}

func streamWriteRange(w: JsonWriter, range: LspRange): Unit {
    w.startObject()
    w.writeName("start")
    streamWritePosition(w, range.start)
    w.writeName("end")
    streamWritePosition(w, range.end)
    w.endObject()
}

func streamWriteSymbol(w: JsonWriter, symbol: DocumentSymbol): Unit {
    w.startObject()
    w.writeName("name").writeValue(symbol.name)
    if (let Some(detail) <- symbol.detail) {
        w.writeName("detail").writeValue(detail)
    }
    w.writeName("kind").writeValue(symbolKindValue(symbol.kind))
    w.writeName("range")
    streamWriteRange(w, symbol.range)
    w.writeName("selectionRange")
    streamWriteRange(w, symbol.selectionRange)
    if (let Some(children) <- symbol.children) {
        w.writeName("children")
        w.startArray()
        for (child in children) {
            streamWriteSymbol(w, child)
        }
        w.endArray()
    }
    w.endObject()
}

func streamResponse(id: Int64, symbols: Array<DocumentSymbol>): Array<Byte> {
    let buffer = ByteBuffer()
    let w = JsonWriter(buffer)
    w.startObject()
    w.writeName("jsonrpc").writeValue("2.0")
    w.writeName("id").writeValue(id)
    w.writeName("result")
    w.startArray()
    for (symbol in symbols) {
        streamWriteSymbol(w, symbol)
    }
    w.endArray()
    w.endObject()
    w.flush()
    readToEnd(buffer)
}

// ---- the two agree ----

@Test
class JsonCodecEquivalenceTest {
    @TestCase
    func theStreamCodecReadsADidOpenAsTheServerDoes() {
        // act
        let current = DidOpenTextDocumentNotificationSpec().decodeParams(currentParams(DID_OPEN_FRAME))
        let stream = streamDidOpen(streamReader(streamEnvelope(DID_OPEN_FRAME).params.getOrThrow()))

        // assert
        @Expect(stream.textDocument.text, current.textDocument.text)
        @Expect(stream.textDocument.text, BENCH_TEXT)
        @Expect(stream.textDocument.uri, current.textDocument.uri)
        @Expect(stream.textDocument.version, current.textDocument.version)
        @Expect(stream.textDocument.languageId.value, current.textDocument.languageId.value)
    }

    @TestCase
    func theStreamCodecReadsBothKindsOfChangeAsTheServerDoes() {
        // act
        let spec = DidChangeTextDocumentNotificationSpec()
        let full = streamDidChange(streamReader(streamEnvelope(DID_CHANGE_FULL_FRAME).params.getOrThrow()))
        let key = streamDidChange(streamReader(streamEnvelope(DID_CHANGE_KEY_FRAME).params.getOrThrow()))
        let currentKey = spec.decodeParams(currentParams(DID_CHANGE_KEY_FRAME))

        // assert
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
        @Expect(key.textDocument.version, currentKey.textDocument.version)
    }

    @TestCase
    func theStreamCodecWritesTheSameResponseAsTheServer() {
        // act
        let current = String.fromUtf8(currentResponse(7, BENCH_RESULT))
        let stream = String.fromUtf8(streamResponse(7, BENCH_SYMBOLS))

        // assert
        @Expect(JsonValue.fromStr(stream).toString(), JsonValue.fromStr(current).toString())
    }
}

// ---- the benchmarks ----

var benchSink: Int64 = 0

@Test
@Configure[warmup: 1 * Duration.second, minDuration: 3 * Duration.second]
class JsonCodecBench {
    // one message, the whole way from bytes to params

    @Bench
    func didOpen64KbCurrent(): Unit {
        benchSink += Int64(DidOpenTextDocumentNotificationSpec().decodeParams(currentParams(DID_OPEN_FRAME)).textDocument.version)
    }

    @Bench
    func didOpen64KbStream(): Unit {
        benchSink += Int64(streamDidOpen(streamReader(streamEnvelope(DID_OPEN_FRAME).params.getOrThrow())).textDocument.version)
    }

    @Bench
    func didChangeFull64KbCurrent(): Unit {
        benchSink += Int64(DidChangeTextDocumentNotificationSpec().decodeParams(currentParams(DID_CHANGE_FULL_FRAME)).textDocument.version)
    }

    @Bench
    func didChangeFull64KbStream(): Unit {
        benchSink += Int64(streamDidChange(streamReader(streamEnvelope(DID_CHANGE_FULL_FRAME).params.getOrThrow())).textDocument.version)
    }

    @Bench
    func didChangeKeystrokeCurrent(): Unit {
        benchSink += Int64(DidChangeTextDocumentNotificationSpec().decodeParams(currentParams(DID_CHANGE_KEY_FRAME)).textDocument.version)
    }

    @Bench
    func didChangeKeystrokeStream(): Unit {
        benchSink += Int64(streamDidChange(streamReader(streamEnvelope(DID_CHANGE_KEY_FRAME).params.getOrThrow())).textDocument.version)
    }

    @Bench
    func documentSymbolRequestCurrent(): Unit {
        benchSink += DocumentSymbolRequestSpec().decodeParams(currentParams(DOCUMENT_SYMBOL_FRAME)).textDocument.uri.size
    }

    @Bench
    func documentSymbolRequestStream(): Unit {
        benchSink += streamDocumentSymbolParams(streamReader(streamEnvelope(DOCUMENT_SYMBOL_FRAME).params.getOrThrow())).textDocument.uri.size
    }

    // one answer, the whole way from the result to bytes

    @Bench
    func documentSymbolResponse550Current(): Unit {
        benchSink += currentResponse(7, BENCH_RESULT).size
    }

    @Bench
    func documentSymbolResponse550Stream(): Unit {
        benchSink += streamResponse(7, BENCH_SYMBOLS).size
    }
}

let DID_OPEN_STRING = String.fromUtf8(DID_OPEN_FRAME)
let DID_OPEN_JSON = JsonValue.fromStr(DID_OPEN_STRING)
let DID_OPEN_DATA_MODEL = DataModel.fromJson(DID_OPEN_JSON)
let DID_OPEN_PARAMS = Body.deserialize(DID_OPEN_DATA_MODEL).getNotificationBodyOrThrow().params
let DID_OPEN_RAW_PARAMS = streamEnvelope(DID_OPEN_FRAME).params.getOrThrow()

let RESULT_DATA_MODEL = DocumentSymbolRequestSpec().encodeResult(BENCH_RESULT)
let RESPONSE_JSON = ResponseBody(Nullable.Value(IntegerOrString.Integer(7)), ResultOrError.Result(RESULT_DATA_MODEL))
    .enveloped()
    .serialize()
    .toJson()
let RESPONSE_STRING = RESPONSE_JSON.toString()

let WHOLE_CHANGE_DATA_MODEL = benchWholeChange("x").serialize()
let PARTIAL_CHANGE_DATA_MODEL = benchPartialChange(1, "x").serialize()

/** Where the time of the codec the server has goes, a stage at a time. */
@Test
@Configure[warmup: 1 * Duration.second, minDuration: 3 * Duration.second]
class JsonCodecStageBench {
    @Bench
    func didOpenStage1Utf8ToString(): Unit {
        benchSink += String.fromUtf8(DID_OPEN_FRAME).size
    }

    @Bench
    func didOpenStage2StringToJsonValue(): Unit {
        benchSink += (JsonValue.fromStr(DID_OPEN_STRING) as JsonObject).getOrThrow().size()
    }

    @Bench
    func didOpenStage3JsonValueToDataModel(): Unit {
        benchSink += (DataModel.fromJson(DID_OPEN_JSON) as DataModelStruct).getOrThrow().getFields().size
    }

    @Bench
    func didOpenStage4DataModelToBody(): Unit {
        benchSink += Body.deserialize(DID_OPEN_DATA_MODEL).getNotificationBodyOrThrow().method.size
    }

    @Bench
    func didOpenStage5DataModelToParams(): Unit {
        benchSink += Int64(DidOpenTextDocumentNotificationSpec().decodeParams(DID_OPEN_PARAMS).textDocument.version)
    }

    @Bench
    func didOpenStreamEnvelopeOnly(): Unit {
        benchSink += streamEnvelope(DID_OPEN_FRAME).params.getOrThrow().size
    }

    @Bench
    func didOpenStreamParamsOnly(): Unit {
        benchSink += Int64(streamDidOpen(streamReader(DID_OPEN_RAW_PARAMS)).textDocument.version)
    }

    @Bench
    func responseStage1ResultToDataModel(): Unit {
        benchSink += (DocumentSymbolRequestSpec().encodeResult(BENCH_RESULT) as DataModelSeq).getOrThrow().getItems().size
    }

    @Bench
    func responseStage2BodyToJsonValue(): Unit {
        let json = ResponseBody(Nullable.Value(IntegerOrString.Integer(7)), ResultOrError.Result(RESULT_DATA_MODEL))
            .enveloped()
            .serialize()
            .toJson()
        benchSink += (json as JsonObject).getOrThrow().size()
    }

    @Bench
    func responseStage3JsonValueToString(): Unit {
        benchSink += RESPONSE_JSON.toString().size
    }

    @Bench
    func responseStage4StringToBytes(): Unit {
        benchSink += RESPONSE_STRING.toArray().size
    }

    // an untagged union tries its variants in turn: the second one pays for the first one's exception

    @Bench
    func untaggedFirstVariant(): Unit {
        if (let TextDocumentContentChangeEvent.AsTextDocumentContentChangePartial(change) <- TextDocumentContentChangeEvent
            .deserialize(PARTIAL_CHANGE_DATA_MODEL)) {
            benchSink += change.text.size
        }
    }

    @Bench
    func untaggedSecondVariant(): Unit {
        if (let TextDocumentContentChangeEvent.AsTextDocumentContentChangeWholeDocument(change) <- TextDocumentContentChangeEvent
            .deserialize(WHOLE_CHANGE_DATA_MODEL)) {
            benchSink += change.text.size
        }
    }
}

/** The same messages, by what they allocate. */
@Test
@Measure[Runtime(AllocatedMemory)]
@Configure[warmup: 100, minDuration: 1 * Duration.second]
class JsonCodecAllocationBench {
    @Bench
    func didOpen64KbCurrent(): Unit {
        benchSink += Int64(DidOpenTextDocumentNotificationSpec().decodeParams(currentParams(DID_OPEN_FRAME)).textDocument.version)
    }

    @Bench
    func didOpen64KbStream(): Unit {
        benchSink += Int64(streamDidOpen(streamReader(streamEnvelope(DID_OPEN_FRAME).params.getOrThrow())).textDocument.version)
    }

    @Bench
    func didChangeKeystrokeCurrent(): Unit {
        benchSink += Int64(DidChangeTextDocumentNotificationSpec().decodeParams(currentParams(DID_CHANGE_KEY_FRAME)).textDocument.version)
    }

    @Bench
    func didChangeKeystrokeStream(): Unit {
        benchSink += Int64(streamDidChange(streamReader(streamEnvelope(DID_CHANGE_KEY_FRAME).params.getOrThrow())).textDocument.version)
    }

    @Bench
    func documentSymbolResponse550Current(): Unit {
        benchSink += currentResponse(7, BENCH_RESULT).size
    }

    @Bench
    func documentSymbolResponse550Stream(): Unit {
        benchSink += streamResponse(7, BENCH_SYMBOLS).size
    }
}

/** The middle way: `Serializable` as it is, its `DataModel` walked straight into a `JsonWriter`. */
func writeDataModel(w: JsonWriter, dm: DataModel): Unit {
    match (dm) {
        case s: DataModelStruct =>
            w.startObject()
            for (field in s.getFields()) {
                w.writeName(field.getName())
                writeDataModel(w, field.getData())
            }
            w.endObject()
        case s: DataModelSeq =>
            w.startArray()
            for (item in s.getItems()) {
                writeDataModel(w, item)
            }
            w.endArray()
        case s: DataModelString => w.writeValue(s.getValue())
        case i: DataModelInt => w.writeValue(i.getValue())
        case f: DataModelFloat => w.writeValue(f.getValue())
        case b: DataModelBool => w.writeValue(b.getValue())
        case _ => w.writeNullValue()
    }
}

func dataModelWriterResponse(id: Int32, result: Nullable<SymbolInformationsOrDocumentSymbols>): Array<Byte> {
    let dm = DocumentSymbolRequestSpec().encodeResult(result)
    let body = ResponseBody(Nullable.Value(IntegerOrString.Integer(id)), ResultOrError.Result(dm)).enveloped()
    let buffer = ByteBuffer()
    let w = JsonWriter(buffer)
    writeDataModel(w, body.serialize())
    w.flush()
    readToEnd(buffer)
}

@Test
class JsonCodecDataModelWriterTest {
    @TestCase
    func walkingTheDataModelWritesTheSameResponseAsTheServer() {
        // act
        let current = String.fromUtf8(currentResponse(7, BENCH_RESULT))
        let walked = String.fromUtf8(dataModelWriterResponse(7, BENCH_RESULT))

        // assert
        @Expect(JsonValue.fromStr(walked).toString(), JsonValue.fromStr(current).toString())
    }
}

@Test
@Configure[warmup: 1 * Duration.second, minDuration: 3 * Duration.second]
class JsonCodecDataModelWriterBench {
    @Bench
    func documentSymbolResponse550DataModelWriter(): Unit {
        benchSink += dataModelWriterResponse(7, BENCH_RESULT).size
    }
}

@Test
@Measure[Runtime(AllocatedMemory)]
@Configure[warmup: 100, minDuration: 1 * Duration.second]
class JsonCodecDataModelWriterAllocationBench {
    @Bench
    func documentSymbolResponse550DataModelWriter(): Unit {
        benchSink += dataModelWriterResponse(7, BENCH_RESULT).size
    }
}

func didOpenDecoder(_: String): (JsonReader) -> DidOpenTextDocumentParams {
    streamDidOpen
}

func didChangeDecoder(_: String): (JsonReader) -> DidChangeTextDocumentParams {
    streamDidChange
}

func documentSymbolDecoder(_: String): (JsonReader) -> DocumentSymbolParams {
    streamDocumentSymbolParams
}

@Test
class JsonCodecOnePassEquivalenceTest {
    @TestCase
    func theOnePassCodecReadsWhatTheServerReads() {
        // act
        let open = streamOnePass(DID_OPEN_FRAME, didOpenDecoder)
        let full = streamOnePass(DID_CHANGE_FULL_FRAME, didChangeDecoder)

        // assert
        @Expect(open.textDocument.text, BENCH_TEXT)
        @Expect(open.textDocument.uri, BENCH_URI)
        match (full.contentChanges[0]) {
            case TextDocumentContentChangeEvent.AsTextDocumentContentChangeWholeDocument(change) =>
                @Expect(change.text, BENCH_TEXT)
            case _ => @Fail("a whole-document change was read as a partial one")
        }
        @Expect(streamOnePass(DOCUMENT_SYMBOL_FRAME, documentSymbolDecoder).textDocument.uri, BENCH_URI)
    }
}

@Test
@Configure[warmup: 1 * Duration.second, minDuration: 3 * Duration.second]
class JsonCodecOnePassBench {
    @Bench
    func didOpen64KbOnePass(): Unit {
        benchSink += Int64(streamOnePass(DID_OPEN_FRAME, didOpenDecoder).textDocument.version)
    }

    @Bench
    func didChangeFull64KbOnePass(): Unit {
        benchSink += Int64(streamOnePass(DID_CHANGE_FULL_FRAME, didChangeDecoder).textDocument.version)
    }

    @Bench
    func didChangeKeystrokeOnePass(): Unit {
        benchSink += Int64(streamOnePass(DID_CHANGE_KEY_FRAME, didChangeDecoder).textDocument.version)
    }

    @Bench
    func documentSymbolRequestOnePass(): Unit {
        benchSink += streamOnePass(DOCUMENT_SYMBOL_FRAME, documentSymbolDecoder).textDocument.uri.size
    }
}

@Test
@Measure[Runtime(AllocatedMemory)]
@Configure[warmup: 100, minDuration: 1 * Duration.second]
class JsonCodecOnePassAllocationBench {
    @Bench
    func didOpen64KbOnePass(): Unit {
        benchSink += Int64(streamOnePass(DID_OPEN_FRAME, didOpenDecoder).textDocument.version)
    }

    @Bench
    func didChangeKeystrokeOnePass(): Unit {
        benchSink += Int64(streamOnePass(DID_CHANGE_KEY_FRAME, didChangeDecoder).textDocument.version)
    }
}
