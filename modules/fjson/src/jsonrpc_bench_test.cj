package fjson

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import stdx.encoding.json.*

/*
 * fjson on what a JSON-RPC connection of the server reads and writes, the envelope included and
 * the params decoded the way a generator would: a keystroke's `didChange` (the most frequent
 * message), a `documentSymbol` request, and the answer to it, 550 symbols with their ranges. What
 * `FjsonBench` leaves out: many small objects, keys and integers rather than one large string.
 *
 * `cjHeapSize=4GB cjpm bench '--filter=FjRpcBench*'`
 */

let KEYSTROKE: Array<Byte> = ##"{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"file:///home/user/project/src/main.cj","version":42},"contentChanges":[{"range":{"start":{"line":120,"character":17},"end":{"line":120,"character":17}},"rangeLength":0,"text":"a"}]}}"##.toArray()

let SYMBOL_REQUEST: Array<Byte> = ##"{"jsonrpc":"2.0","id":7,"method":"textDocument/documentSymbol","params":{"textDocument":{"uri":"file:///home/user/project/src/main.cj"}}}"##.toArray()

struct RpcPosition {
    RpcPosition(let line: UInt32, let character: UInt32) {}
}

struct RpcRange {
    RpcRange(let start: RpcPosition, let end: RpcPosition) {}
}

struct RpcChange {
    RpcChange(let range: ?RpcRange, let rangeLength: ?UInt32, let text: String) {}
}

struct RpcDidChange {
    RpcDidChange(let uri: String, let version: Int32, let changes: Array<RpcChange>) {}
}

struct RpcSymbol {
    RpcSymbol(let name: String, let detail: ?String, let kind: Int64, let range: RpcRange, let selectionRange: RpcRange,
        let children: ?Array<RpcSymbol>) {}
}

let RPC_SYMBOLS: Array<RpcSymbol> = Array<RpcSymbol>(50) {
    c =>
    let methods = Array<RpcSymbol>(10) {
        m =>
        let line = UInt32(c * 100 + m * 9 + 1)
        RpcSymbol("method${m}OfClass${c}", "(a: Int64, b: String): Unit", 6,
            RpcRange(RpcPosition(line, 4), RpcPosition(line + 7, 5)), RpcRange(RpcPosition(line, 9), RpcPosition(line, 20)), None)
    }
    let line = UInt32(c * 100)
    RpcSymbol("Class${c}", None, 5, RpcRange(RpcPosition(line, 0), RpcPosition(line + 95, 1)),
        RpcRange(RpcPosition(line, 6), RpcPosition(line, 12)), methods)
}

func rpcRequired<T>(value: ?T, name: String): T {
    value ?? throw FjException("missing `${name}`")
}

/** The envelope in one pass, `params` decoded in place when `method` came first, as the connection will. */
func rpcRead<P>(r: FjReader, decode: (String, FjReader) -> P): (?Int64, P) {
    var method: ?String = None
    var id: ?Int64 = None
    var params: ?P = None
    var raw: ?Array<Byte> = None
    r.beginObject()
    while (r.nextKey()) {
        if (r.keyIs("jsonrpc")) {
            if (r.readString() != "2.0") {
                throw FjException("not 2.0")
            }
        } else if (r.keyIs("id")) {
            id = r.readInt64()
        } else if (r.keyIs("method")) {
            method = r.readString()
        } else if (r.keyIs("params")) {
            match (method) {
                case Some(m) => params = decode(m, r)
                case None => raw = r.rawValue()
            }
        } else {
            r.skipValue()
        }
    }
    r.end()
    match ((params, raw)) {
        case (Some(p), _) => (id, p)
        case (None, Some(bytes)) =>
            r.reset(bytes)
            (id, decode(rpcRequired(method, "method"), r))
        case _ => throw FjException("no params")
    }
}

func rpcPosition(r: FjReader): RpcPosition {
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
    RpcPosition(rpcRequired(line, "line"), rpcRequired(character, "character"))
}

func rpcRange(r: FjReader): RpcRange {
    var start: ?RpcPosition = None
    var end: ?RpcPosition = None
    r.beginObject()
    while (r.nextKey()) {
        if (r.keyIs("start")) {
            start = rpcPosition(r)
        } else if (r.keyIs("end")) {
            end = rpcPosition(r)
        } else {
            r.skipValue()
        }
    }
    RpcRange(rpcRequired(start, "start"), rpcRequired(end, "end"))
}

func rpcChange(r: FjReader): RpcChange {
    var range: ?RpcRange = None
    var rangeLength: ?UInt32 = None
    var text: ?String = None
    r.beginObject()
    while (r.nextKey()) {
        if (r.keyIs("range")) {
            range = rpcRange(r)
        } else if (r.keyIs("rangeLength")) {
            rangeLength = r.readUInt32()
        } else if (r.keyIs("text")) {
            text = r.readString()
        } else {
            r.skipValue()
        }
    }
    RpcChange(range, rangeLength, rpcRequired(text, "text"))
}

func rpcDidChange(_: String, r: FjReader): RpcDidChange {
    var uri: ?String = None
    var version: ?Int32 = None
    var changes: ?Array<RpcChange> = None
    r.beginObject()
    while (r.nextKey()) {
        if (r.keyIs("textDocument")) {
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
        } else if (r.keyIs("contentChanges")) {
            let list = ArrayList<RpcChange>()
            r.beginArray()
            while (r.nextItem()) {
                list.add(rpcChange(r))
            }
            changes = list.toArray()
        } else {
            r.skipValue()
        }
    }
    RpcDidChange(rpcRequired(uri, "uri"), rpcRequired(version, "version"), rpcRequired(changes, "contentChanges"))
}

func rpcSymbolParams(_: String, r: FjReader): String {
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
    rpcRequired(uri, "uri")
}

let NAME_character = FjName("character")
let NAME_children = FjName("children")
let NAME_detail = FjName("detail")
let NAME_end = FjName("end")
let NAME_id = FjName("id")
let NAME_jsonrpc = FjName("jsonrpc")
let NAME_kind = FjName("kind")
let NAME_line = FjName("line")
let NAME_name = FjName("name")
let NAME_range = FjName("range")
let NAME_result = FjName("result")
let NAME_selectionRange = FjName("selectionRange")
let NAME_start = FjName("start")

func rpcWritePosition(w: FjWriter, position: RpcPosition): Unit {
    w.beginObject()
    w.name(NAME_line)
    w.uint32(position.line)
    w.name(NAME_character)
    w.uint32(position.character)
    w.endObject()
}

func rpcWriteRange(w: FjWriter, range: RpcRange): Unit {
    w.beginObject()
    w.name(NAME_start)
    rpcWritePosition(w, range.start)
    w.name(NAME_end)
    rpcWritePosition(w, range.end)
    w.endObject()
}

func rpcWriteSymbol(w: FjWriter, symbol: RpcSymbol): Unit {
    w.beginObject()
    w.name(NAME_name)
    w.string(symbol.name)
    if (let Some(detail) <- symbol.detail) {
        w.name(NAME_detail)
        w.string(detail)
    }
    w.name(NAME_kind)
    w.int64(symbol.kind)
    w.name(NAME_range)
    rpcWriteRange(w, symbol.range)
    w.name(NAME_selectionRange)
    rpcWriteRange(w, symbol.selectionRange)
    if (let Some(children) <- symbol.children) {
        w.name(NAME_children)
        w.beginArray()
        for (child in children) {
            rpcWriteSymbol(w, child)
        }
        w.endArray()
    }
    w.endObject()
}

func rpcWriteResponse(w: FjWriter, id: Int64, symbols: Array<RpcSymbol>): Array<Byte> {
    w.beginObject()
    w.name(NAME_jsonrpc)
    w.string("2.0")
    w.name(NAME_id)
    w.int64(id)
    w.name(NAME_result)
    w.beginArray()
    for (symbol in symbols) {
        rpcWriteSymbol(w, symbol)
    }
    w.endArray()
    w.endObject()
    w.bytes()
}

@Test
class FjRpcBenchFixtureTest {
    @TestCase
    func theMessagesReadAndWriteAsTheyShould() {
        // act
        let (_, change) = rpcRead(FjReader(KEYSTROKE), rpcDidChange)
        let (id, uri) = rpcRead(FjReader(SYMBOL_REQUEST), rpcSymbolParams)
        let written = JsonValue.fromStr(String.fromUtf8(rpcWriteResponse(FjWriter(), 7, RPC_SYMBOLS))).asObject()

        // assert
        @Expect(change.version, 42)
        @Expect(change.changes[0].range?.start.character, Some(UInt32(17)))
        @Expect(change.changes[0].text, "a")
        @Expect(id, Some(7))
        @Expect(uri, "file:///home/user/project/src/main.cj")
        let symbols = written.get("result").getOrThrow().asArray()
        @Expect(symbols.size(), 50)
        let method = symbols.get(3).getOrThrow().asObject().get("children").getOrThrow().asArray().get(2).getOrThrow()
            .asObject()
        @Expect(method.get("name").getOrThrow().asString().getValue(), "method2OfClass3")
        let end = method.get("range").getOrThrow().asObject().get("end").getOrThrow().asObject()
        @Expect(end.get("line").getOrThrow().asInt().getValue(), 3 * 100 + 2 * 9 + 1 + 7)
    }
}

var rpcSink = 0

let RPC_READER = FjReader(Array<Byte>())
let RPC_WRITER = FjWriter()

@Test
@Configure[warmup: 1 * Duration.second, minDuration: 3 * Duration.second]
class FjRpcBench {
    @Bench
    func readKeystroke(): Unit {
        RPC_READER.reset(KEYSTROKE)
        rpcSink += rpcRead(RPC_READER, rpcDidChange)[1].changes.size
    }

    @Bench
    func readSymbolRequest(): Unit {
        RPC_READER.reset(SYMBOL_REQUEST)
        rpcSink += rpcRead(RPC_READER, rpcSymbolParams)[1].size
    }

    @Bench
    func readDidOpen64Kb(): Unit {
        RPC_READER.reset(DID_OPEN)
        rpcSink += fjsonText(RPC_READER).size
    }

    @Bench
    func write550SymbolResponse(): Unit {
        RPC_WRITER.clear()
        rpcSink += rpcWriteResponse(RPC_WRITER, 7, RPC_SYMBOLS).size
    }
}

@Test
@Measure[Runtime(AllocatedMemory)]
@Configure[warmup: 100, minDuration: 1 * Duration.second]
class FjRpcAllocationBench {
    @Bench
    func readKeystroke(): Unit {
        RPC_READER.reset(KEYSTROKE)
        rpcSink += rpcRead(RPC_READER, rpcDidChange)[1].changes.size
    }

    @Bench
    func readDidOpen64Kb(): Unit {
        RPC_READER.reset(DID_OPEN)
        rpcSink += fjsonText(RPC_READER).size
    }

    @Bench
    func write550SymbolResponse(): Unit {
        RPC_WRITER.clear()
        rpcSink += rpcWriteResponse(RPC_WRITER, 7, RPC_SYMBOLS).size
    }
}
