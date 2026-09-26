# ADR-0014: Diagnostics are pulled; pushed, by the server after a write, only to clients that cannot pull

Status: accepted, 2026-09-26

## Context

- cjls reported no errors. The syntactic ones are all there: `parse` returns them in `Parse.errors`, with their `TextRange`s, and the parser was checked against the compiler's test suite with no false errors.
- LSP delivers diagnostics two ways. Pull (`textDocument/diagnostic`, 3.17): the client asks, as for any request; VS Code and Neovim ≥ 0.10 do. Push (`textDocument/publishDiagnostics`): the server sends them when the files change; every client takes it, and some (Emacs `eglot`, older Neovim) take nothing else.
- A push needs work after a write, which nothing scheduled (Q4): a `Context` handler runs no query (S1), a `readonly` one runs only when asked.
- salsa reports from nested queries through accumulators; calca has none, rust-analyzer does not use them, and ty keeps diagnostics in its results.

## Decision

- **Pull first.** `textDocument/diagnostic` is a `readonly` handler like `documentSymbol`: `loupe.diagnostics(db, fileId)`, translated in `to_proto.cj`. Advertised with `interFileDependencies: false`, `workspaceDiagnostics: false`. A `Cancelled` pull is answered `ServerCancelled` with `retriggerRequest: true`, so the client asks again.
- **Push only to a client that cannot pull.** `initialize` keeps whether the client declared `textDocument.diagnostic`; one that did is never pushed to, so one file never has two sources racing (S8).
- **The server schedules the push, not a handler** (S7). After a `Context` handler returns having changed the files, `Server` takes a snapshot on the read loop and hands a `spawn` the open documents as they are then; the `spawn` publishes one notification per document. `Cancelled` there is dropped: the write that cancelled it scheduled its own. A generation per document, checked before `notify`, drops a publish overtaken by a newer one (S9). `didClose` publishes an empty list at once.
- **`Client.notify` takes an `LspOutboundNotification<P>` spec**, as `route` takes an inbound one: no method strings.
- **A parse error is data.** `ginkgo` records a `ParseError<K>` — `Expected(kind)` for what `Parser.expect` misses, `Message` for the rest — and `cjsyntax.message` words it (`expected '}'`): `ginkgo` spells no kind, and a fix (insert the missing token) or a diagnostic code reads the kind, not the text.
- **No accumulators.** Diagnostics are part of the queries' results (`Parse.errors` now, validation and semantics later) (A11).

## Consequences

- VS Code and Neovim get diagnostics with nothing new in the server; the push path serves the rest.
- The server now runs work of its own after a write: the same mechanism is what reading the disk on a `spawn` (#12) and `semanticTokens/refresh` (#16) need.
- Every change re-publishes every open document. Cheap while `parse` is memoized and diagnostics are syntactic; revisit when semantic ones make it costly.
- No `resultId`, `unchanged` reports or `workspace/diagnostic` yet (Q9, Q10).
- Q4 is closed.
