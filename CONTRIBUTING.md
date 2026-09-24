# Contributing

Build, test and commit conventions are in [CLAUDE.md](CLAUDE.md#build--test). This file covers the one change made most often.

## Adding a request or notification

Handlers live in `modules/cjls/src/handlers` (package `cjls.handlers`), one file per feature: `hover.cj`, `document_sync.cj`, …

1. **Find the spec.** Every message the client sends has a generated `<TypeName>Spec` in `cjls.lsp_types` — `HoverRequestSpec`, `DidOpenTextDocumentNotificationSpec`. It fixes the method, the params type and the result type.

2. **Write the handler** as a plain function in the feature's file. Params come last; before them, take only what the handler uses:

   ```cangjie
   func handleHover(db: DatabaseSnapshot, cancellation: CancellationToken, params: HoverParams): Nullable<Hover> {
       ...
   }
   ```

   | argument | available to |
   |---|---|
   | `Database` | `route` only — the handler that changes the inputs |
   | `DatabaseSnapshot` | `readonly` only |
   | `Client`, `CancellationToken`, `Logger` | both |
   | `Context` / `ReadOnlyContext` | both — all of the above at once, for a handler that needs more than three |

   The `Logger` already carries the method and request id; add attributes rather than formatting them into the message.

3. **Register it** with one line in `handlers/router.cj`:

   - `.route(spec, handler)` if it changes state (`didOpen`, `didChange`, configuration). It runs on the read loop, in arrival order, and nothing else is read until it returns — keep it short.
   - `.readonly(spec, handler)` if it only answers a question (`hover`, `definition`, `completion`). It runs on a thread of its own against a snapshot taken when the message arrived. This is the default for requests.

   Registering a handler under the wrong one does not compile: `Database` cannot be taken by a `readonly` handler.

4. **Advertise it** in `capabilities()` in `handlers/router.cj`, or clients will never send it.

5. **Test the function directly**, next to it in `<feature>_test.cj`: it is an ordinary function, so call it with the arguments it takes. Only behaviour of the server itself — lifecycle, dispatch, threading — is tested through `Server`, in `cjls.server`.

Don't await a `Client.request` from a `route` handler: its answer can only arrive through the read loop that the handler is holding.
