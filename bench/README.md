# JSON codec candidates (issue #9)

What `modules/cjls/src/handlers/json_codec_*_bench_test.cj` measures against the server's own codec. Not part of the
server: workspace members only so the stdx paths of the root manifest reach them.

| dir | what | changed from upstream |
|---|---|---|
| `cangjieJSON` | gitcode.com/Cangjie-TPC/cangjieJSON (`cjjson`), `@JsonAdapter` over `stdx.encoding.json`'s `JsonValue` | manifest only: `static`, cjc 1.3; tests and examples left out |
| `CJson` | gitcode.com/Cangjie-TPC/CJson, `@JsonSerializable` over `JsonValue`, written for cjc 0.55 | manifest; `encoding.json` → `stdx.encoding.json`; collections' `add` for `put`/`append` |
| `fjson` | ours: a pull reader over the frame's bytes and a writer into one byte buffer, no tree | — |

```sh
cjpm test '--filter=JsonCodec*Test.*'             # every variant reads and writes what the server does
cjpm test '--filter=Fj*'                           # fjson's own tests
cjHeapSize=4GB cjpm bench '--filter=JsonCodec*'   # timings and allocations
```
