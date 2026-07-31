# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`cjls` is a Language Server Protocol implementation for the **Cangjie** language, written in Cangjie itself. It is an early-stage MVP, and the work has proceeded bottom-up: the `jsonrpc` transport/peer layer is built and covered by tests, while the LSP layer above it is largely still to be written — `modules/cjls/src/run_server.cj` is a stub with the old server loop commented out, the protocol types are meant to be generated from `metaModel.json` and are not yet, and the handler-registration macros are partly stubs.

Read `modules/jsonrpc/DESIGN.md` before touching the RPC layer: it is the agreed target design (layering, concurrency, error-code and null modelling) and it records *why* several decisions went the way they did.

## Build & test

The toolchain is `cjpm` (Cangjie package manager / `cjc`). It is not on `PATH` by default — source the SDK env first (once per shell):

```
source ~/.cangjie/envsetup.sh
```

Then, from the repo root:

- `cjpm build` — build the workspace
- `cjpm run` — build and run the `cjls` server executable
- `cjpm test` — run all tests (this is what the `pre-push` git hook runs)
- `cjpm clean` — clean build outputs
- Run a subset of tests: `cjpm test '--filter=ConnectionCloseTest.*'` — filter is `<TestClass>.<testCase>`, `*` wildcards allowed. Quote it: the user's shell is fish, which glob-expands an unquoted `*`.

`cjpm` leaves expansion artifacts (`*.cj.macrocall`, `lib-macro_*.dylib`) next to the sources in `src/`. They are untracked build output, not code — ignore them, never edit them.

### stdx dependency bootstrap (important)

The project depends on the external `stdx` library via `bin-dependencies` pointing at `third_party/stdx`. That path is **not** checked in — `build.cj` runs as a `pre-build` build script and symlinks `third_party/stdx` from the `CANGJIE_STDX_PATH` environment variable. If a build fails resolving `stdx.*` imports, confirm `CANGJIE_STDX_PATH` is set and `third_party/stdx` exists (currently symlinked to `~/.cangjie/third_party/stdx/static/stdx`). `cjpm test --skip-script` skips the script when the symlink is already in place.

### Commits

Conventional Commits are enforced by commitlint via a husky `commit-msg` hook. Use `type(scope): subject` (e.g. `feat(jsonrpc): ...`); commitizen (`cz-conventional-changelog`) is configured.

## Workspace layout

Four members declared in the root `cjpm.toml`, each its own package:

- **`modules/stdxx`** (`dynamic`) — foundation library: the sum types the protocol needs (`IntegerOrString`, `ArrayOrObject`, `Nullable`), the `DataModel` helpers that go with them (`data_model.cj`), their exceptions (`exception.cj`), plus a `deriving` **macro package** for `@DeriveExt[...]` codegen. No project dependencies.
- **`modules/jsonrpc`** (`dynamic`) — the JSON-RPC peer: model, codec, framed transport, `Connection`. Knows **zero method names**. Depends on `stdxx`.
- **`modules/cjls`** (`executable`) — the server: entrypoint, logging, and the `cjls.macros` macro package for handler registration. Depends on `jsonrpc`.
- **`modules/lsp_codegen`** (`executable`) — placeholder for the generator that will turn `modules/cjls/metaModel.json` into typed LSP structs. Currently a hello-world `main`.

Dependencies flow one way: `cjls → jsonrpc → stdxx`. `lsp_codegen` stands alone.

## Architecture

### `jsonrpc` — a symmetric peer, not a server

Layered exactly as `DESIGN.md` describes; all four layers are implemented:

- **L1 model** (`body.cj`, `error.cj`) — `Body` is an enum of `Request(RequestBody) | Notification(NotificationBody) | Response(ResponseBody)`; `ResultOrError` and `RequestId = IntegerOrString` sit with it, while `ResponseError` and `ErrorCode` live in `error.cj` — that is where the `lsp`-level codes get appended. `ErrorCode` is an **open `Int32` newtype**, not a closed enum, so unknown codes survive a round-trip; new codes get added as further constants rather than by changing the type.
- **L2 codec** (`body.cj`, `Body.serialize`/`deserialize`) — JSON-RPC has no discriminator field, so the *shape* is the discriminator: presence of `id`/`method`/`result`/`error` decides the variant.
- **L3 transport** (`transport.cj`) — `JsonRpcReader`/`JsonRpcWriter`/`JsonRpcTransport` interfaces (all `<: Resource`) with `FramedJsonRpcTransport` implementing `Content-Length` framing over any `InputStream`/`OutputStream` pair; `header.cj` parses the framing. Interfaces so stdio, sockets and in-memory pipes are interchangeable.
- **L4 connection** (`connection.cj`) — owns the read loop, id correlation, concurrency, and per-request cancellation. Outbound `request`/`notify`; inbound arrives at a `Handler` (`handler.cj`) the layer above implements.

**Threading.** `serve()` owns the read loop; each inbound request/notification gets a `spawn`. A `Mutex`-guarded `send` keeps frames intact. Outbound correlation uses a capacity-1 `LinkedBlockingQueue` as a one-shot: the read loop fills it, `PendingRequest.await()` blocks the *caller's own* thread on it. **Gotcha:** a `spawn`ed thread that throws dumps its stack to stderr even if nobody reads the future — so every `spawn` boundary catches internally.

**Two exception types, two meanings** (`exception.cj`) — keep them straight when adding code:

- `RpcException` — the frame was bad but **the stream is still in sync**. Answerable: it carries a `ResponseError`, and the read loop replies with it and keeps reading.
- `TransportException` — **the framing itself is lost**. There is no next message to find; the loop ends.

**Lifecycle.** Transports and `Connection` implement `Resource` (`isClosed()`/`close()`, so `try-with-resource` works). `close()` is idempotent and safe from any thread — it is the only way to end a `serve()` loop blocked on a read from this side. Closing settles everything outstanding rather than leaving it dangling: the transport is closed, in-flight handlers get their tokens cancelled, and every caller waiting in `await()` is woken with an error. The same applies when the peer hangs up — `serve()` abandons pending requests as it unwinds, so no `await()` can outlive its connection. When adding a shutdown path, preserve that invariant.

### Serialization: `DataModel`, and the two independent null axes

Serialization goes through `stdx.serialization`'s `DataModel` (`Serializable<T>`: `serialize(): DataModel` / `static deserialize(dm: DataModel): T`), currently hand-written per type. `@DeriveExt[...]` in `stdxx.deriving` is the intended codegen for this and is **still a stub that returns its input**.

LSP treats *optional* and *nullable* as two independent axes, and this codebase mirrors that with two composable types — the mapping is mechanical, no judgment per field:

| protocol shape | Cangjie type | on write |
|---|---|---|
| required, non-null | `T` | always |
| optional | `field!: ?T = None` | **omitted** when `None` — never written as `null` |
| nullable | `Nullable<T>` | always; `Null` → JSON `null` |
| optional **and** nullable | `?Nullable<T>` | omit `None`; `Some(Null)` → `null`; `Some(Value v)` → `v` |

**Read-side caveat:** `DataModelStruct.get(key)` returns `DataModelNull` for an *absent* key, collapsing `undefined` and explicit `null`. Use the presence-aware `DataModelStruct.getOrNone` extension (`modules/stdxx/src/data_model.cj`) whenever the distinction matters — `Body.deserialize` depends on it to tell a notification (no `id`) from a response with a null `id`.

It is carried by a `DataModelFields` interface rather than a bare `extend`, because Cangjie exports a direct `extend` only to the package that declares it — an extension meant to cross a package boundary needs an interface to travel with, and `import stdxx.*` then brings it along. Any further `DataModel` helper that the layers above need should be added the same way.

### `cjls` — entrypoint, logging, handler macros

`main.cj` initializes the global logger then calls `runServer()`, catching `ProtocolStateException` (protocol invariant violations) separately from other exceptions. Logging (`logging.cj`) wraps `stdx.log` with a global `SimpleLogger` to stderr, a `[cjls]` prefix, and a level from the `CJLS_LOG_LEVEL` env var (default `INFO`). Use `logInfo`/`logError`/`logDebug`/etc. rather than printing — stdout is the LSP wire.

The intended registration pattern, via the `cjls.macros` macro package:

1. Annotate a type with `@LspRequest["method", params: P, result: R]` (or `@LspNotification[method: "...", params: P]`), containing a `@LspHandle`-annotated static `handle` func.
2. The macro generates an `extend` exposing `METHOD` and a uniform `handle(params, ctx)`. `@LspNotification`'s `buildHandleCall` maps the user's handler params **by name**: a param named `params` receives the message params, any other name is pulled from `ctx.<name>`.
3. `@LspHandlers[requests: [...], notifications: [...]]` generates the router — which is exactly the `Handler` interface `jsonrpc` expects. jsonrpc never interprets a method string; routing is entirely this layer's job.

**Current state:** `@LspNotification` is the most complete; `@LspRequest` and `@LspHandlers` bodies still just return their input (`extendLspRequest` exists but is unused). The interfaces those macros generate against (`LspRequest`, `LspNotification`, `GlobalContext`) do **not currently exist** — they went away with the old `lsp` module and are to be reintroduced above `jsonrpc`. Expect to build this out rather than assume it works.

### Macro-package mechanics

Macros live in dedicated `macro package` files (`cjls.macros`, `stdxx.deriving`) and use `std.ast.*`. Shared helpers are in `macros/utils.cj` (`lexAttrs` for parsing attribute arguments, `Decl.getGenericFragments()` for propagating generics into generated `extend`s). Generated code is emitted as `quote(...)` templates with `$`-interpolation — the output must be valid Cangjie against the target interfaces. A macro package compiles even when the code it *emits* would not, so a green build is no evidence the codegen is correct.

## Testing conventions

Tests live beside the code as `*_test.cj` in the same package, using `std.unittest` (`@Test` class / `@TestCase` func, `@Expect`/`@Assert`/`@AssertThrows`, `@Configure[randomSeed:]` + `@TestCase[x in random()]` for property tests). Cases follow an `// arrange` / `// act` / `// assert` layout, and are named as sentences describing the behaviour (`closeWakesACallerWaitingForAnAnswer`).

Concurrency is tested deterministically, never with sleeps: `connection_test.cj` drives a `FakeTransport` whose queues let a test block until the connection actually writes, and hands the handler a lambda that parks on a `LinkedBlockingQueue` until the test releases it. Follow that pattern instead of timing assumptions.
