#!/usr/bin/env python3
# Writes modules/fjson/src/base_bench_test.cj: fjson as of REV renamed Base*, and the jsonrpc
# bench over it, so a bench run measures the baseline and the change side by side.
# usage (repo root): gen_base.py [REV [BENCH_REV]] — BENCH_REV holds the jsonrpc bench's decoders
import subprocess, re, sys
rev = sys.argv[1] if len(sys.argv) > 1 else 'feat/fjson'
bench_rev = sys.argv[2] if len(sys.argv) > 2 else rev
def show(p, at=None):
    return subprocess.run(['git', 'show', f'{at or rev}:modules/fjson/src/{p}'], capture_output=True, text=True, check=True).stdout
def body(src):
    src = re.sub(r'^package fjson\n', '', src)
    src = re.sub(r'^import .*\n', '', src, flags=re.M)
    return src
lib = body(show('scan.cj')) + body(show('reader.cj')) + body(show('writer.cj'))
# drop what is shared unchanged: the exception, the kind enum
lib = re.sub(r'public class FjException.*?\n}\n', '', lib, flags=re.S)
lib = re.sub(r'public enum FjKind \{.*?\}\n', '', lib, flags=re.S)
renames = {
    'FjReader': 'BaseReader', 'FjWriter': 'BaseWriter',
    'scanAscii': 'baseScanAscii', 'scanEscapes': 'baseScanEscapes', 'utf8Length': 'baseUtf8Length',
    'QUOTE': 'BASE_QUOTE', 'BACKSLASH': 'BASE_BACKSLASH', 'MAX_DEPTH': 'BASE_MAX_DEPTH', 'HEX': 'BASE_HEX',
}
def rename(s):
    for a, b in renames.items():
        s = re.sub(rf'\b{a}\b', b, s)
    return s
lib = rename(lib)
bench = show('jsonrpc_bench_test.cj', bench_rev)
# the decoders and writers only, from rpcRequired's end to the fixture test
start = bench.index('/** The envelope in one pass')
end = bench.index('@Test\nclass FjRpcBenchFixtureTest')
coders = bench[start:end]
coders = re.sub(r'\bfunc rpc(\w)', lambda m: 'func baseRpc' + m.group(1), coders)
coders = re.sub(r'\brpc(Read|Position|Range|Change|DidChange|SymbolParams|WritePosition|WriteRange|WriteSymbol|WriteResponse)\b',
                lambda m: 'baseRpc' + m.group(1), coders)
coders = rename(coders)
fjtext = re.search(r'/\*\* The text of a `didOpen`.*?\n}\n', show('fjson_bench_test.cj', bench_rev), re.S).group(0)
fjtext = rename(fjtext.replace('func fjsonText', 'func baseText'))
out = f'''package fjson

import std.collection.*
import std.convert.*
import std.unittest.*
import std.unittest.testmacro.*

/* GENERATED for the A/B of the perf experiments: fjson as of `{rev}`, renamed. Not for merging. */
{lib}
{coders}
{fjtext}
var baseSink = 0

let BASE_READER = BaseReader(Array<Byte>())
let BASE_WRITER = BaseWriter()

@Test
@Configure[warmup: 1 * Duration.second, minDuration: 3 * Duration.second]
class FjRpcBaseBench {{
    @Bench
    func readKeystroke(): Unit {{
        BASE_READER.reset(KEYSTROKE)
        baseSink += baseRpcRead(BASE_READER, baseRpcDidChange)[1].changes.size
    }}

    @Bench
    func readSymbolRequest(): Unit {{
        BASE_READER.reset(SYMBOL_REQUEST)
        baseSink += baseRpcRead(BASE_READER, baseRpcSymbolParams)[1].size
    }}

    @Bench
    func readDidOpen64Kb(): Unit {{
        BASE_READER.reset(DID_OPEN)
        baseSink += baseText(BASE_READER).size
    }}

    @Bench
    func write550SymbolResponse(): Unit {{
        BASE_WRITER.clear()
        baseSink += baseRpcWriteResponse(BASE_WRITER, 7, RPC_SYMBOLS).size
    }}
}}
'''
open('modules/fjson/src/base_bench_test.cj', 'w').write(out)
