# Contributing

Build, test and commit conventions are in [CLAUDE.md](CLAUDE.md#build--test). This file covers the one change made most often.

## Adding a request or notification

Handlers live in `modules/cjls/src/handlers` (package `cjls.handlers`), one file per feature: `hover.cj`, `document_sync.cj`, …

1. **Find the spec.** Every message the client sends has a generated `<TypeName>Spec` in `cjls.lsp_types` — `HoverRequestSpec`, `DidOpenTextDocumentNotificationSpec`. It fixes the method, the params type and the result type.

2. **Write the handler** as a plain function in the feature's file, marked `@LspHandler` (from `cjls.macros`). Params come last; before them, take only what the handler uses:

   ```cangjie
   @LspHandler[readonly]
   func handleHover(snap: ServerSnapshot, cancellation: CancellationToken, params: HoverParams): Nullable<Hover> {
       ...
   }
   ```

   - `@LspHandler[readonly]` if it only answers a question (`hover`, `definition`, `completion`) — the default for requests. It runs on a thread of its own against a snapshot taken when the message arrived.
   - `@LspHandler` if it changes state (`didOpen`, `didChange`, configuration). It runs on the read loop, in arrival order, and nothing else is read until it returns — keep it short.

   | argument | available to |
   |---|---|
   | `ServerState` | `@LspHandler` only — the handler that changes the inputs |
   | `ServerSnapshot` | `@LspHandler[readonly]` only |
   | `Client`, `CancellationToken`, `Logger` | both |

   Taking one the mode doesn't offer fails to compile. The `Logger` already carries the method and request id; add attributes rather than formatting them into the message.

   A handler only translates ([S3](docs/design/01-request-slice.md)): `from_proto.cj` gives the document (`fileOf(snap, uri)`) and offsets (`offsetOf(snap, file, position)`), a function of `loupe` does the work on `snap.analysis`, and `to_proto.cj` turns its answer into LSP types, through the snapshot's text and `snap.encoding`. `handlers/document_symbol.cj` is the example. Logic that is not translation goes to `loupe`, tested there. Don't catch `Cancelled`: the server answers `ContentModified` or `RequestCancelled` for it ([D8](docs/adr/0008-cancellation.md)).

3. **Register it** with one line in `handlers/router.cj`: `.route(HoverRequestSpec(), handleHover)`. A one-liner can be a lambda instead, its context annotated: `.route(ShutdownRequestSpec()) {_: Context<Unit> => ()}`.

4. **Advertise it** in `capabilities()` in `handlers/router.cj`, or clients will never send it.

5. **Record what you decided** in `docs/` if it is a new rule or decision ([docs/README.md](docs/README.md)).

6. **Test the function directly**, next to it in `<feature>_test.cj`: call it with the arguments it takes (`ServerState().snapshot()`, `CancellationToken()`, `NoopLogger()`, …). Only behaviour of the server itself — lifecycle, dispatch, threading — is tested through `Server`, in `cjls.server`. An end-to-end test in `tests/e2e` is for what only the built binary shows — one or two per feature, not a case each ([C7](docs/design/03-conventions.md)).

Don't await a `Client.request` from a `@LspHandler` without `readonly`: its answer can only arrive through the read loop that the handler is holding.
