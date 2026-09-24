# Request slice

## Read request (`textDocument/documentSymbol`)

| Thread | Step | Where |
|---|---|---|
| read loop | frame → `Body.Request` → `InboundRequest(id, token)` | `Connection.serve` |
| read loop | lifecycle check → `ReadOnly` route | `Server.onRequest` |
| read loop | **snapshot taken here**, with `cancelledBy: token` | `Database.snapshot` |
| spawn | `decodeParams` → `P` (else `INVALID_PARAMS`) | route |
| spawn | `T.from(ctx)` per parameter | `@LspHandler` adapter |
| spawn | URI → `SourceFile`, `Position` → offset | `from_proto.cj` |
| spawn | `fileStructure(db.analysis, fileId)` | `loupe` |
| spawn | offsets → `Range` via the snapshot's rope | `to_proto.cj` |
| spawn | `encodeResult` → respond | `Server.answer` |

## Write notification (`textDocument/didChange`)

| Thread | Step | Where |
|---|---|---|
| read loop | `Exclusive` route, in arrival order | `Server.onNotification` |
| read loop | edits → `Rope.replace`, in the encoding agreed on | `handleDidChange` |
| read loop | `Vfs` → `takeChanges` → `RootDatabase.applyChanges` | `Database.setFileContents` |
| read loop | calca: cancel in-flight snapshot queries, wait for them, new revision | `Runtime.write` |

## Server push (`textDocument/publishDiagnostics`) — not built (Q4)

| Thread | Step |
|---|---|
| read loop | after an `Exclusive` handler changed the files: snapshot |
| spawn | `loupe.diagnostics(db, fileId)` per open document → `client.notify` |
| spawn | `Cancelled` → drop silently: the next change schedules its own |

## Cancellation (D8)

| Cause | Mechanism | Answer |
|---|---|---|
| a file changed | `Runtime.write` cancels in-flight queries; a stale snapshot is `Cancelled` | `ContentModified` |
| `$/cancelRequest` | token → snapshot's `cancelledBy` → next calca call throws `Cancelled` | `RequestCancelled` |
| connection closed | every token cancelled | dropped |

## Rules

| # | Rule |
|---|---|
| S1 | A `Context` handler never runs a query: it only changes inputs, and it is short. |
| S2 | A `readonly` handler reads everything from its snapshot: `FileId`, text for positions (`file.text(db.analysis)`, never the `Vfs`), encoding. |
| S3 | Handlers only translate; logic goes to `loupe`. Conversion lives in `from_proto.cj` / `to_proto.cj`. |
| S4 | Unknown document → empty answer (`null`, `[]`); `RpcException` only for bad params. |
| S5 | Never catch `Cancelled` in a handler; the server maps it (see table). |
| S6 | Handlers are not `@CalcaTracked` (D6). |
