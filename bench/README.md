# JSON codec candidates (issue #9)

What `modules/cjls/src/handlers/json_codec_*_bench_test.cj` measures against the server's own codec. Not part of the
server: workspace members only so the stdx paths of the root manifest reach them.

| dir | what | changed from upstream |
|---|---|---|
| `cangjieJSON` | gitcode.com/Cangjie-TPC/cangjieJSON (`cjjson`), `@JsonAdapter` over `stdx.encoding.json`'s `JsonValue` | manifest only: `static`, cjc 1.3; tests and examples left out |
| `CJson` | gitcode.com/Cangjie-TPC/CJson, `@JsonSerializable` over `JsonValue`, written for cjc 0.55 | manifest; `encoding.json` → `stdx.encoding.json`; collections' `add` for `put`/`append` |
| `fjson` | ours: a pull reader over the frame's bytes and a writer into one byte buffer, no tree | — |

## Results

cjc 1.3.0-alpha.20260918, `-O2`, static stdx, darwin arm64, load average 3–6 (2026-09-26). Median time; allocations
are deterministic. "stdx stream" is `stdx.encoding.json.stream` in one pass; fjson "reused" keeps one reader and
one writer from message to message, as a connection's read loop would.

| bytes → params | current | stdx stream | cangjieJSON | CJson | fjson | fjson reused |
|---|---:|---:|---:|---:|---:|---:|
| `didOpen`, 64 KB | 217 µs | 316 µs | 231 µs | 217 µs | **125 µs** | **115 µs** |
| `didChange` full, 64 KB | 222 µs | 332 µs | 225 µs | 220 µs | **127 µs** | |
| `didChange`, one keystroke | 4.05 µs | 1.59 µs | 1.46 µs | 1.52 µs | **0.57 µs** | **0.54 µs** |
| `documentSymbol` request | 2.13 µs | 0.83 µs | 0.68 µs | 0.65 µs | **0.28 µs** | |
| allocated, `didOpen` 64 KB | 684 KiB | 475 KiB | 677 KiB | 677 KiB | 480 KiB | **166 KiB** |
| allocated, one keystroke | 12.8 KiB | 10.7 KiB | 6.1 KiB | 8.3 KiB | 0.82 KiB | **0.45 KiB** |

| result → bytes (550 symbols) | current | stdx stream | cangjieJSON | CJson | fjson | fjson reused |
|---|---:|---:|---:|---:|---:|---:|
| time | 1.60 ms | 315 µs | 1.26 ms | 1.13 ms¹ | **231 µs** | **223 µs** |
| allocated | 4.12 MiB | 0.83 MiB | 4.22 MiB | 4.23 MiB¹ | 0.56 MiB | **0 B** |

¹ not the server's answer: CJson writes an absent `detail`/`children` as `null`.

- cangjieJSON and CJson are `JsonValue` trees underneath: on a large message they cost what `JsonValue.fromStr`
  does, and on a write what `JsonValue.toString` does. They beat the current path on small messages only by
  skipping `DataModel` and `Body`. Neither takes an `enum` (no untagged union), both want `var` fields and a
  constructor without parameters; CJson cannot omit a key.
- fjson's `swar: true` (eight bytes at a time through `acquireArrayRawData`) is 3.3× *slower* on `didOpen` (417 µs)
  and 1.4× on the write (317 µs): each acquire costs ~100 ns, and LSP text has an escape every few dozen bytes.
- `params` before `method` costs fjson a skip and a re-read of a slice, no copy: 193 µs for `didOpen`.

```sh
cjpm test '--filter=JsonCodec*Test.*'             # every variant reads and writes what the server does
cjpm test '--filter=Fj*'                           # fjson's own tests
cjHeapSize=4GB cjpm bench '--filter=JsonCodec*'   # timings and allocations
```
