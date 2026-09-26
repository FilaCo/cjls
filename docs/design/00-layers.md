# Layers

## Modules and packages (D3)

| | When |
|---|---|
| module | a library that knows nothing of the server: own dependencies, own `output-type`, reusable without `cjls` |
| package of `cjls` | everything only the server has |

- A package is Cangjie's unit of compilation: a module buys no build parallelism.
- A module boundary is what the compiler checks: `loupe` cannot import `cjls.lsp_types`, because it does not depend on `cjls`.
- Nothing can depend on an executable module (`cjls`).

## Dependencies

```
cjls ──> jsonrpc ──> stdxx
  │
  └────> loupe ──> calca
           ├─────> cjsyntax ──> ginkgo
           ├─────> index_map
           └─────> rope
```

Inside `cjls`: `handlers → server`, `handlers → loupe`. Inside `loupe`: `loupe → syntax → db → vfs`.

`loupe`'s packages are layers, as rust-analyzer's crates are (`vfs`, `base-db`, `syntax`/`hir`, `ide`), never features: a package depends only on those under it, so a query of `loupe.syntax` never sees the API. A feature (`fileStructure`, `diagnostics`, `highlight`, later `hover`) is a file of the API package `loupe`, free to call the others and every query under it. What two features share is a query of a layer below (a resolved name, a type), not a call from one to the other; a layer gets its own package when queries need one (`loupe.hir`), not when a feature appears.

Outside the chain for now, `fjson`, on nothing: the JSON codec `jsonrpc` moves onto once it holds up against the JSON test suites (Q20).

Outside the chain, generators run by hand: `lsp_codegen` (`cjls.lsp_types`) and `syntax_codegen` (`SyntaxKind`, `cjsyntax.ast`, D10), on `cjtoml` and `stdxx`.

## Layers of a request

| # | Layer | Where | Knows | Down the boundary |
|---|---|---|---|---|
| L0 | transport | `jsonrpc` | bytes, `Content-Length` | `Body` |
| L1 | connection | `jsonrpc.Connection` | ids, `CancellationToken` per request | `InboundRequest`, `(method, params)` |
| L2 | server | `cjls.server` | lifecycle, handler mode, error codes | `Parts` + raw params |
| L3 | route | `Router`, `*Spec` | message types | `Context<P>` / `ReadOnlyContext<P>` |
| L4 | handler | `cjls.handlers` | LSP ⇄ loupe translation only | `FileId`, byte offsets, loupe types |
| L5 | API | `loupe` | what an editor asks, no LSP | query calls |
| L6 | queries | `loupe.syntax`, later `loupe.hir` | `@CalcaTracked`, keyed by entities | input reads |
| L7 | inputs | `loupe.db`, `loupe.vfs` | files, `SourceFile.text` | — |

Above L4/L5: URIs, `Position`, encodings. Below: `FileId`, UTF-8 byte offsets, `TextRange` (D5).
