# Request slice

## Read request (`textDocument/documentSymbol`)

| Thread | Step | Where |
|---|---|---|
| read loop | frame → `Body.Request` → `InboundRequest(id, token)` | `Connection.serve` |
| read loop | lifecycle check → `ReadOnly` route | `Server.onRequest` |
| read loop | **snapshot taken here**, with `cancelledBy: token` | `ServerState.snapshot` |
| spawn | `decodeParams` → `P` (else `INVALID_PARAMS`) | route |
| spawn | `T.from(ctx)` per parameter | `@LspHandler` adapter |
| spawn | URI → `SourceFile`, `Position` → offset | `from_proto.cj` |
| spawn | `fileStructure(snap.analysis, fileId)` | `loupe` |
| spawn | offsets → `Range` via the snapshot's rope | `to_proto.cj` |
| spawn | `encodeResult` → respond | `Server.answer` |

Every read request takes this path; only the `loupe` call and its translation differ. Which ones the server answers is `handlers/router.cj`.

## Write notification (`textDocument/didChange`)

| Thread | Step | Where |
|---|---|---|
| read loop | `Exclusive` route, in arrival order | `Server.onNotification` |
| read loop | edits → `Rope.replace`, in the encoding agreed on | `handleDidChange` |
| read loop | `Vfs` → `takeChanges` → `AnalysisDatabase.applyChanges` | `ServerState.setFileContents` |
| read loop | calca: cancel in-flight snapshot queries, wait for them, new revision | `Runtime.write` |

## Server push (`textDocument/publishDiagnostics`, D14)

Only for a client that cannot pull (`initialize` found no `textDocument.diagnostic`, kept in `ServerState`).

| Thread | Step | Where |
|---|---|---|
| read loop | an `Exclusive` handler (request or notification) returned, having changed the files or opened a document | `Server.writing` |
| read loop | snapshot; the open documents with their `version`, and a new generation for each | `DiagnosticsPush.schedule` |
| spawn | per open document: `diagnostics(snap.analysis, fileId)` → LSP `Diagnostic`s | `documentDiagnostics`, `to_proto.cj` |
| spawn | generation still the document's latest → `client.notify(PublishDiagnosticsNotificationSpec(), …)` with its `version`; else dropped | `DiagnosticsPush.publish` |
| spawn | `Cancelled` → dropped, `DEBUG`: the write that cancelled it scheduled its own | `DiagnosticsPush.schedule` |
| spawn | the connection closed → dropped, `DEBUG`; anything else → `ERROR`, nothing sent | `DiagnosticsPush.schedule` |

`didClose` publishes an empty list for the document at once, on the read loop, so its errors do not stay in the editor.

## Cancellation (D8)

| Cause | Mechanism | Answer |
|---|---|---|
| a file changed | `Runtime.write` cancels in-flight queries; a stale snapshot is `Cancelled` | `ContentModified`; `ServerCancelled` with `retriggerRequest: true` for `textDocument/diagnostic` (D14) |
| `$/cancelRequest` | token → snapshot's `cancelledBy` → next calca call throws `Cancelled` | `RequestCancelled` |
| connection closed | every token cancelled | dropped |
| a push overtaken by a write | its snapshot is `Cancelled`, or its generation is no longer the latest | nothing sent |

## Rules

| # | Rule |
|---|---|
| S1 | A `Context` handler never runs a query: it only changes inputs, and it is short. |
| S2 | A `readonly` handler reads everything from its snapshot: `FileId`, text for positions (`file.text(snap.analysis)`, never the `Vfs`), encoding. |
| S3 | Handlers only translate; logic goes to `loupe`. Conversion lives in `from_proto.cj` / `to_proto.cj`. |
| S4 | Unknown document → empty answer (`null`, `[]`, an empty report); `RpcException` only for bad params. |
| S5 | Never catch `Cancelled` in a handler; the server maps it (see table). |
| S6 | Handlers are not `@CalcaTracked` (D6). |
| S7 | Work after a write is scheduled by the server, not by a handler: it takes the snapshot on the read loop, after the `Context` handler returned, and runs the queries on a `spawn` (D14). |
| S8 | One source of diagnostics per client: a client that pulls is never pushed to (D14). |
| S9 | A push never overwrites a newer one: a publish whose generation is not its document's latest is dropped before `notify`. |
