package fjson

import std.io.*
import std.unittest.*
import std.unittest.testmacro.*
import stdx.encoding.json.*
import stdx.encoding.json.stream.*

/*
 * fjson against stdx's two JSON APIs, on the shapes that dominate an LSP server's traffic: a
 * large string (a `didOpen` of 64 KB of code) read, and many small objects (an outline of 550
 * symbols) written. The same comparison on the server's own messages, and against cangjieJSON
 * and CJson, is on branch `worktree-json-codec-candidates` (#9).
 *
 * `cjHeapSize=4GB cjpm bench '--filter=FjsonBench*'`
 */

let BENCH_TEXT: String = {
    =>
    let line = "    let greeting = \"héllo, \\\"мир\\\"\\t\" // a comment 😀\n"
    let sb = StringBuilder()
    while (sb.size < 64 * 1024) {
        sb.append(line)
    }
    sb.toString()
}()

let DID_OPEN: Array<Byte> = {
    =>
    let document = JsonObject()
    document.put("uri", JsonString("file:///home/user/project/src/main.cj"))
    document.put("languageId", JsonString("cangjie"))
    document.put("version", JsonInt(1))
    document.put("text", JsonString(BENCH_TEXT))
    let params = JsonObject()
    params.put("textDocument", document)
    let message = JsonObject()
    message.put("jsonrpc", JsonString("2.0"))
    message.put("method", JsonString("textDocument/didOpen"))
    message.put("params", params)
    message.toString().toArray()
}()

struct BenchSymbol {
    BenchSymbol(let name: String, let detail: String, let kind: Int64, let line: Int64, let children: Array<BenchSymbol>) {}
}

let BENCH_SYMBOLS: Array<BenchSymbol> = Array<BenchSymbol>(50) {
    c =>
    let methods = Array<BenchSymbol>(10) {
        m => BenchSymbol("method${m}OfClass${c}", "(a: Int64, b: String): Unit", 6, c * 100 + m * 9 + 1, [])
    }
    BenchSymbol("Class${c}", "", 5, c * 100, methods)
}

/** The text of a `didOpen`, read by fjson the way a generated decoder reads it. */
func fjsonText(r: FjReader): String {
    var text = ""
    r.beginObject()
    while (r.nextKey()) {
        if (r.keyIs("params")) {
            r.beginObject()
            while (r.nextKey()) {
                if (r.keyIs("textDocument")) {
                    r.beginObject()
                    while (r.nextKey()) {
                        if (r.keyIs("text")) {
                            text = r.readString()
                        } else {
                            r.skipValue()
                        }
                    }
                } else {
                    r.skipValue()
                }
            }
        } else {
            r.skipValue()
        }
    }
    text
}

func streamText(bytes: Array<Byte>): String {
    let buffer = ByteBuffer()
    buffer.write(bytes)
    let r = JsonReader(buffer)
    var text = ""
    r.startObject()
    while (r.peek() != Some(JsonToken.EndObject)) {
        if (r.readName() != "params") {
            r.skip()
            continue
        }
        r.startObject()
        while (r.peek() != Some(JsonToken.EndObject)) {
            if (r.readName() != "textDocument") {
                r.skip()
                continue
            }
            r.startObject()
            while (r.peek() != Some(JsonToken.EndObject)) {
                if (r.readName() == "text") {
                    text = r.readValue<String>()
                } else {
                    r.skip()
                }
            }
            r.endObject()
        }
        r.endObject()
    }
    r.endObject()
    text
}

func treeText(bytes: Array<Byte>): String {
    let message = JsonValue.fromStr(String.fromUtf8(bytes)).asObject()
    let document = message.get("params").getOrThrow().asObject().get("textDocument").getOrThrow().asObject()
    document.get("text").getOrThrow().asString().getValue()
}

func fjsonSymbol(w: FjWriter, symbol: BenchSymbol): Unit {
    w.beginObject()
    w.name("name")
    w.string(symbol.name)
    if (!symbol.detail.isEmpty()) {
        w.name("detail")
        w.string(symbol.detail)
    }
    w.name("kind")
    w.int64(symbol.kind)
    w.name("line")
    w.int64(symbol.line)
    if (!symbol.children.isEmpty()) {
        w.name("children")
        w.beginArray()
        for (child in symbol.children) {
            fjsonSymbol(w, child)
        }
        w.endArray()
    }
    w.endObject()
}

func fjsonSymbols(w: FjWriter): Array<Byte> {
    w.beginArray()
    for (symbol in BENCH_SYMBOLS) {
        fjsonSymbol(w, symbol)
    }
    w.endArray()
    w.bytes()
}

func streamSymbol(w: JsonWriter, symbol: BenchSymbol): Unit {
    w.startObject()
    w.writeName("name").writeValue(symbol.name)
    if (!symbol.detail.isEmpty()) {
        w.writeName("detail").writeValue(symbol.detail)
    }
    w.writeName("kind").writeValue(symbol.kind)
    w.writeName("line").writeValue(symbol.line)
    if (!symbol.children.isEmpty()) {
        w.writeName("children")
        w.startArray()
        for (child in symbol.children) {
            streamSymbol(w, child)
        }
        w.endArray()
    }
    w.endObject()
}

func streamSymbols(): Array<Byte> {
    let buffer = ByteBuffer()
    let w = JsonWriter(buffer)
    w.startArray()
    for (symbol in BENCH_SYMBOLS) {
        streamSymbol(w, symbol)
    }
    w.endArray()
    w.flush()
    readToEnd(buffer)
}

func treeSymbol(symbol: BenchSymbol): JsonValue {
    let o = JsonObject()
    o.put("name", JsonString(symbol.name))
    if (!symbol.detail.isEmpty()) {
        o.put("detail", JsonString(symbol.detail))
    }
    o.put("kind", JsonInt(symbol.kind))
    o.put("line", JsonInt(symbol.line))
    if (!symbol.children.isEmpty()) {
        o.put("children", JsonArray(symbol.children.map(treeSymbol)))
    }
    o
}

func treeSymbols(): Array<Byte> {
    JsonArray(BENCH_SYMBOLS.map(treeSymbol)).toString().toArray()
}

@Test
class FjsonBenchFixtureTest {
    @TestCase
    func everyVariantReadsAndWritesTheSame() {
        // act
        let fjsonRead = fjsonText(FjReader(DID_OPEN))
        let written = String.fromUtf8(fjsonSymbols(FjWriter()))

        // assert
        @Expect(fjsonRead, BENCH_TEXT)
        @Expect(streamText(DID_OPEN), BENCH_TEXT)
        @Expect(treeText(DID_OPEN), BENCH_TEXT)
        @Expect(JsonValue.fromStr(written).toString(), JsonValue.fromStr(String.fromUtf8(treeSymbols())).toString())
        @Expect(JsonValue.fromStr(written).toString(), JsonValue.fromStr(String.fromUtf8(streamSymbols())).toString())
    }
}

var benchSink = 0

/** One reader and one writer, kept from one message to the next as a connection would. */
let READER = FjReader(Array<Byte>())
let WRITER = FjWriter()

@Test
@Configure[warmup: 1 * Duration.second, minDuration: 3 * Duration.second]
class FjsonBench {
    @Bench
    func readDidOpen64KbFjson(): Unit {
        READER.reset(DID_OPEN)
        benchSink += fjsonText(READER).size
    }

    @Bench
    func readDidOpen64KbStdxStream(): Unit {
        benchSink += streamText(DID_OPEN).size
    }

    @Bench
    func readDidOpen64KbStdxJsonValue(): Unit {
        benchSink += treeText(DID_OPEN).size
    }

    @Bench
    func write550SymbolsFjson(): Unit {
        WRITER.clear()
        benchSink += fjsonSymbols(WRITER).size
    }

    @Bench
    func write550SymbolsStdxStream(): Unit {
        benchSink += streamSymbols().size
    }

    @Bench
    func write550SymbolsStdxJsonValue(): Unit {
        benchSink += treeSymbols().size
    }
}

@Test
@Measure[Runtime(AllocatedMemory)]
@Configure[warmup: 100, minDuration: 1 * Duration.second]
class FjsonAllocationBench {
    @Bench
    func readDidOpen64KbFjson(): Unit {
        READER.reset(DID_OPEN)
        benchSink += fjsonText(READER).size
    }

    @Bench
    func readDidOpen64KbStdxStream(): Unit {
        benchSink += streamText(DID_OPEN).size
    }

    @Bench
    func readDidOpen64KbStdxJsonValue(): Unit {
        benchSink += treeText(DID_OPEN).size
    }

    @Bench
    func write550SymbolsFjson(): Unit {
        WRITER.clear()
        benchSink += fjsonSymbols(WRITER).size
    }

    @Bench
    func write550SymbolsStdxStream(): Unit {
        benchSink += streamSymbols().size
    }

    @Bench
    func write550SymbolsStdxJsonValue(): Unit {
        benchSink += treeSymbols().size
    }
}
