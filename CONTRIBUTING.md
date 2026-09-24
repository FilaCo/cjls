# Contributing

Build, test and commit conventions are in [CLAUDE.md](CLAUDE.md#build--test). This file covers the one change made most often.

## Adding a request or notification

Handlers live in `modules/cjls/src/handlers` (package `cjls.handlers`), one file per feature: `hover.cj`, `document_sync.cj`, …

1. **Find the spec.** Every message the client sends has a generated `<TypeName>Spec` in `cjls.lsp_types` — `HoverRequestSpec`, `DidOpenTextDocumentNotificationSpec`. It fixes the method, the params type and the result type.

2. **Write the handler** as a plain function in the feature's file, marked `@LspHandler` (from `cjls.macros`). Params come last; before them, take only what the handler uses:

   ```cangjie
   @LspHandler[readonly]
   func handleHover(db: DatabaseSnapshot, cancellation: CancellationToken, params: HoverParams): Nullable<Hover> {
       ...
   }
   ```

   - `@LspHandler[readonly]` if it only answers a question (`hover`, `definition`, `completion`) — the default for requests. It runs on a thread of its own against a snapshot taken when the message arrived.
   - `@LspHandler` if it changes state (`didOpen`, `didChange`, configuration). It runs on the read loop, in arrival order, and nothing else is read until it returns — keep it short.

   | argument | available to |
   |---|---|
   | `Database` | `@LspHandler` only — the handler that changes the inputs |
   | `DatabaseSnapshot` | `@LspHandler[readonly]` only |
   | `Client`, `CancellationToken`, `Logger` | both |

   Taking one the mode doesn't offer fails to compile. The `Logger` already carries the method and request id; add attributes rather than formatting them into the message.

3. **Register it** with one line in `handlers/router.cj`: `.route(HoverRequestSpec(), handleHover)`. A one-liner can be a lambda instead, its context annotated: `.route(ShutdownRequestSpec()) {_: Context, _ => ()}`.

4. **Advertise it** in `capabilities()` in `handlers/router.cj`, or clients will never send it.

5. **Test the function directly**, next to it in `<feature>_test.cj`: call it with the arguments it takes (`Database().snapshot()`, `CancellationToken()`, `NoopLogger()`, …). Only behaviour of the server itself — lifecycle, dispatch, threading — is tested through `Server`, in `cjls.server`.

Don't await a `Client.request` from a `@LspHandler` without `readonly`: its answer can only arrive through the read loop that the handler is holding.
