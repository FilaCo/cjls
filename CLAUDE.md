# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`cjls` is a Language Server Protocol implementation for the **Cangjie** language, written in Cangjie itself. It is an early-stage MVP, built bottom-up: the `jsonrpc` peer, the generated protocol types (messages included), and a handler framework with the lifecycle (`initialize`/`shutdown`/`exit`) are in place and tested; the server advertises no capabilities yet, and the query-driven incremental frontend that will answer real requests is still to be written.

There are no separate design documents: they went stale faster than the code moved and were removed on purpose. The code, its tests and this file are the source of truth — don't recreate a DESIGN.md, and don't argue with the current code on the strength of an old design.

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

### Everything must be statically linked (important)

Every workspace library is `output-type = "static"`, and the stdx it links against must be the **static** one. This is load-bearing, not incidental: cjc 1.1.3 does not emit the funcTable for stdx's `extend<T> Array<T> <: Serializable<Array<T>>` at a user-defined `T` across a shared-library boundary. Flip any package on a serialization path to `dynamic` — or point at the dynamic stdx — and generic dispatch on `Array<SomeType>` (`dms.getDeserializedOrThrow<Array<Request>>(…)`, or `Array<T>.deserialize(dm)` inside a generic func) aborts the process:

```
F funcTable is nullptr, ti: std.core:Array<pkg:T>, itf: ...Serializable<...>
```

It is a SIGABRT from the runtime, not a catchable exception, it compiles perfectly cleanly, and the message names stdx rather than the call site — so it reads like a serialization bug when it is a linkage one. Measured across the full matrix (intermediate lib × stdx, static/dynamic): only static×static survives. **Check `grep output-type modules/*/cjpm.toml` and which stdx the build links against before suspecting the serialization code.** If some package ever genuinely has to be dynamic, the escape hatch is deserializing arrays element-wise, so only the element type crosses the generic boundary.

The `cjls` executable goes one step further: it is linked with `--static` (its `package-configuration` in `modules/cjls/cjpm.toml`, so the flag reaches the executable alone — on the libraries it is only a warning), which takes std and the Cangjie runtime in too. The binary depends on nothing but the system's `libc++`/`libSystem` and runs without the SDK env — which an editor launching it never has. Without it the binary aborts in `dyld` (`@rpath/libcangjie-std-*.dylib`, no `LC_RPATH`). Measured on cjc 1.3.0-alpha, darwin:

- cjpm passes **no `-O`** to cjc, and cjc's default is `-O0` — hence `-O2` in the workspace `compile-option`.
- LTO, and so bitcode (`.bc`) static libraries, are refused on Darwin (`Darwin does not support LTO`), `--experimental` or not; it is a Linux-only option.
- `-dead_strip` shrinks the binary but the runtime aborts on the first message (`Check failed: objectTi != nullptr`): the linker drops type metadata the runtime reaches indirectly. Don't add it.
- Most of the binary's code is whatever runtime packages drag in, not ours: anything reachable from `cjls` that implements `std.ast`'s `ToTokens` links `std.ast` *and the compiler's C++ parser under it* — about two thirds of `__text`. Keep `std.ast` out of runtime packages.

### Commits

Conventional Commits are enforced by commitlint via a husky `commit-msg` hook. Use `type(scope): subject` (e.g. `feat(jsonrpc): ...`); commitizen (`cz-conventional-changelog`) is configured.

## Workspace layout

Five members declared in the root `cjpm.toml`, each its own package:

- **`modules/stdxx`** (`static`) — foundation library: the sum types the protocol needs (`IntegerOrString`, `ArrayOrObject`, `Nullable`), `AnyValue` (a serializable `DataModel`, which `LSPAny` aliases — an imported type can't be extended with an imported interface, so `DataModel` itself never can be), the `DataModel` helpers that go with them (`data_model.cj`), their exceptions (`exception.cj`), plus a `deriving` **macro package** for `@DeriveExt[...]` codegen. No project dependencies.
- **`modules/jsonrpc`** (`static`) — the JSON-RPC peer: model, codec, framed transport, `Connection`. Knows **zero method names**. Depends on `stdxx`.
- **`modules/cjls`** (`executable`) — the server: entrypoint, logging, the handlers, and the `cjls.server` framework they run in. Depends on `jsonrpc`.
- **`modules/cjtoml`** (`static`) — a vendored TOML parser/encoder (Huawei, Apache-2.0 with Runtime Library Exception), carried in-tree because `stdx` ships no TOML module. Its public entry point is `unmarshal<T>(path: String): T where T <: Serializable<T>` — it takes a **file path**, not TOML text. Third-party code: keep it byte-identical to upstream, and never run `cjfmt` over it.
- **`modules/lsp_codegen`** (`executable`) — the generator that turns `modules/lsp_codegen/metaModel.json` into typed LSP declarations in `modules/cjls/src/lsp_types` (generated, checked in, never hand-edited — regenerate instead; delete the old files first, the generator does not prune). It takes the meta model path on the command line and everything else from a TOML config passed with `-c`/`--config` (`modules/cjls/lsp_codegen.toml`): `cjpm run --name lsp_codegen -- modules/lsp_codegen/metaModel.json -c modules/cjls/lsp_codegen.toml`. The config declares only `output-subpackage`; the output directory and the root package name are inherited from the `cjpm.toml` next to it (`src-dir`, defaulting to `src`, and `[package] name`), because cjpm requires every subpackage to be named `<package name>.<path under src-dir>`. A relative `src-dir` resolves against the config file's own directory, not the cwd.

  What it emits, and why:
  - **Structures** are flattened — `extends` then `mixins` then own properties, a redeclared property replacing the inherited one in place — into structs with all-named primary constructor parameters and `@DeriveExtSerializable[skipNone]`. A string-literal property (`kind: 'create'`) becomes the struct's `tag:`/`value:` rather than a field. An anonymous literal type is declared as a struct named `<Owner><Property>`, the owner being the structure that *declares* the property — one inheriting it reuses that type rather than declaring its own. A union of two literals, or an alias of a union holding one, has no name to give them, and the generator refuses it rather than merging them.
  - **Unions** (`or` minus `null`) become untagged enums. The name is the alias defining that union if there is one (the first such alias; later ones become `public type Declaration = Definition`), else the members joined with `Or` in the order first met (`StringOrMarkupContent`, arrays plural: `LocationOrLocations`). Variants are ordered by required-key count, most first, so a struct whose keys are a subset of another's can't answer for it. A `[uinteger, uinteger]` member is a two-payload variant.
  - **Every union variant is `As<Member>`** (`AsBoolean(Bool)`, `AsHoverOptions(HoverOptions)`). Not style: an enum constructor is in scope throughout its package *unqualified*, so a variant named `HoverOptions` makes `HoverOptions` a constructor everywhere in `lsp_types` and the struct no type at all — and qualifying the payload type with the package doesn't get past it. The same scoping is why an optional field of `TextDocumentSyncKind` (which has a `None` variant) defaults to `Option<TextDocumentSyncKind>.None`.
  - **Messages** become field-less structs named by their `typeName` plus `Spec` (`InitializeRequestSpec`, `DidOpenTextDocumentNotificationSpec`): a value of one names the message where its handler is registered — `.route(InitializeRequestSpec(), handleInitialize)` — and brings the method (static `METHOD`, and instance `method` for whoever holds a value) and the types along. The direction is in the type: a message the client sends implements `LspInboundRequest<P, R>` / `LspInboundNotification<P>`, one the server sends `LspOutboundRequest<P, R>` / `LspOutboundNotification<P>`, one going both ways (`$/progress`) both. Only an inbound spec can be routed, and only it has the codec: `decodeParams` (absent params read as `null`; ones that do not decode are an `RpcException` with `INVALID_PARAMS`) and, for a request, `encodeResult`. LSP's `void` — no params (`exit`), a bare `null` result (`shutdown`) — is `Unit` in the spec (`LspInboundRequest<Unit, Unit>`). That is why the codec is written out per spec rather than inherited: only the generator knows whether there is anything to decode or encode, and `Unit`, a type of `std`, can never be made `Serializable` — with the codec on the spec, the routes need no `Serializable` bound and no overload per shape. Partial results, error data and registration options are resolved, so the types they name exist, but not yet part of the spec.
  - **Doc comments** have `/*` and `*/` escaped: block comments nest in Cangjie, so a glob in the documentation would swallow the rest of the file.

All three libraries are `static` deliberately — see the linking constraint above.

Dependencies flow one way: `cjls → jsonrpc → stdxx`. `lsp_codegen` sits outside that chain, on `cjtoml` (which depends on nothing) and `stdxx`.

## Architecture

### `jsonrpc` — a symmetric peer, not a server

Four layers, all implemented:

- **L1 model** (`body.cj`, `error.cj`) — `Body` is an enum of `Request(RequestBody) | Notification(NotificationBody) | Response(ResponseBody)`; `ResultOrError` and `RequestId = IntegerOrString` sit with it, while `ResponseError` and `ErrorCode` live in `error.cj` — that is where the `lsp`-level codes get appended. `ErrorCode` is an **open `Int32` newtype**, not a closed enum, so unknown codes survive a round-trip; new codes get added as further constants rather than by changing the type.
- **L2 codec** (`body.cj`, `Body.serialize`/`deserialize`) — JSON-RPC has no discriminator field, so the *shape* is the discriminator: presence of `id`/`method`/`result`/`error` decides the variant.
- **L3 transport** (`transport.cj`) — `JsonRpcReader`/`JsonRpcWriter`/`JsonRpcTransport` interfaces (all `<: Resource`) with `FramedJsonRpcTransport` implementing `Content-Length` framing over any `InputStream`/`OutputStream` pair; `header.cj` parses the framing. Interfaces so stdio, sockets and in-memory pipes are interchangeable.
- **L4 connection** (`connection.cj`) — owns the read loop, id correlation, concurrency, and per-request cancellation. Outbound `request`/`notify`; inbound arrives at a `Handler` (`handler.cj`) the layer above implements.

**Threading.** `serve()` owns the read loop and hands every inbound message to the `Handler` **on that loop, one at a time, in arrival order** — so `didChange` can never overtake the `didOpen` before it, and nothing more is read until a callback returns. Where work actually runs is the layer above's call: a request arrives as an `InboundRequest` (`inbound_request.cj`) carrying the one right to answer it, which a handler may use in place (`respond`) or carry off to its own `spawn` and answer from there (`respondWith` maps a throw to an error response, so it is a safe `spawn` body). Only the first answer goes out; a handler that throws before answering gets the error response sent on its behalf. **Never `await()` an outbound request from inside a callback** — its answer can only arrive through the read loop the callback is holding. A `Mutex`-guarded `send` keeps frames intact. Outbound correlation uses a capacity-1 `LinkedBlockingQueue` as a one-shot: the read loop fills it, `PendingRequest.await()` blocks the *caller's own* thread on it. **Gotcha:** a `spawn`ed thread that throws dumps its stack to stderr even if nobody reads the future — so every `spawn` boundary catches internally.

**Two exception types, two meanings** (`exception.cj`) — keep them straight when adding code:

- `RpcException` — the frame was bad but **the stream is still in sync**. Answerable: it carries a `ResponseError`, and the read loop replies with it and keeps reading.
- `TransportException` — **the framing itself is lost**. There is no next message to find; the loop ends.

**Lifecycle.** Transports and `Connection` implement `Resource` (`isClosed()`/`close()`, so `try-with-resource` works). `close()` is idempotent and safe from any thread — it is the only way to end a `serve()` loop blocked on a read from this side. Closing settles everything outstanding rather than leaving it dangling: the transport is closed, in-flight handlers get their tokens cancelled, and every caller waiting in `await()` is woken with an error. The same applies when the peer hangs up — `serve()` abandons pending requests as it unwinds, so no `await()` can outlive its connection. When adding a shutdown path, preserve that invariant.

### Serialization: `DataModel`, and the two independent null axes

Serialization goes through `stdx.serialization`'s `DataModel` (`Serializable<T>`: `serialize(): DataModel` / `static deserialize(dm: DataModel): T`). `@DeriveExt[Serializable]` in `stdxx.deriving` generates it for a `struct` or `class` whose fields are its primary constructor parameters, and for an `enum` in any of three shapes. Note that `std.deriving`'s `@Derive` cannot be taught new interfaces — `std.deriving.api`, where its own derivings register, is `protected` to the `std` module — hence the separate macro. When both are applied to one declaration, `@DeriveExt` has to be the outer one: macros expand inside out, so it appends to whatever `@Derive` emitted. If a `Serializable` type with an array field aborts with `funcTable is nullptr`, the cause is linkage, not this code — see the static-linking section above.

One marker configures it — `@DeriveExtSerializable[...]`, the way a single `#[serde(...)]` serves serde's derives. It is legal only inside `@DeriveExt` (it carries its options there through `setItem`/`getChildMessages` and expands to nothing), it works out where it sits from the declaration it was given, and the options follow from that position: `skipNone`, `tag: "kind"` and `transparent` on a type (plus `value: "create"` on a tagged struct), `rename: "textDocument"` and `skipNone` on a field, `value: "URI"` / `value: -32700`, `payload: ["key", "value"]` and `other` on an enum variant. Anything misplaced, misspelled, or spelled as a flag when it takes a value is a diagnostic. Names default to the identifier with its backquotes stripped, so `` `type` `` needs no marker.

**One marker per declaration is load-bearing, not just tidy:** cjc 1.3.0-alpha aborts with an internal error when *any* two macros are stacked on a primary constructor parameter, so a second marker macro must never be added — put the option inside the one that is there. **And** `Nullable<T>` is recognised by its name in the source, so a field declared through an import alias of it reads as a plain optional and loses the `null`-vs-absent distinction.

**Structs.** The fields are the primary constructor parameters in declaration order; a default value does not make a field optional, the type does. Every type parameter of a generic declaration gets `Serializable<T>` appended to its bounds. `tag: "kind", value: "create"` makes a struct carry that constant field — LSP marks `CreateFile`/`DeleteFile` and the progress reports this way — written first, and checked before any other field on read, because an untagged union takes the first variant that reads and such structs often differ in the tag alone.

**Newtypes.** `transparent` makes a one-field struct travel as that field alone — how `lsp_codegen` emits an open enumeration (`ErrorCodes(-32700)` is a bare `-32700`). The field has to be required, and it takes no options: its name never reaches the wire.

**Enums.** No payload anywhere → the enum *is* the value (a string, or integers when `value:` says so; all variants must agree). One variant of such an enum may be `other` with a single payload of the values' kind (`Unknown(UInt32)`): whatever no other variant claims is read into it and written back as is. `lsp_codegen` gives every closed enumeration an `Unknown` of this kind, because a client may send values newer than our metaModel — a capability's `valueSet` does — and one of them would otherwise fail the whole message. Payloads and no `tag:` → untagged, the variant is whichever one the value reads as, tried in declaration order — any failure, an integer overflow included, moves on to the next — so order them narrowest first. A variant with several payloads (`Offsets(UInt32, UInt32)`) is a tuple and travels as an array of exactly that length — Cangjie's own tuple types can't be `extend`ed, so they can never be `Serializable`. `tag: "kind"` → internally tagged, `value:` gives the tag and `payload:` names the positional payload, which follows the same optional/`skipNone` rules a field does. Duplicate wire names and duplicate variant values are diagnostics.

LSP treats *optional* and *nullable* as two independent axes, and this codebase mirrors that with two composable types — the mapping is mechanical, no judgment per field:

| protocol shape | Cangjie type | on read | on write |
|---|---|---|---|
| required, non-null | `T` | throws when absent | always |
| optional | `field!: ?T = None` | absent and `null` both give `None` | `null` when `None` — `skipNone` omits the key instead |
| nullable | `Nullable<T>` | `Null` when `null` | always; `Null` → JSON `null` |
| optional **and** nullable | `?Nullable<T>` | absent → `None`, `null` → `Some(Null)` | `null` for either; `Some(Value v)` → `v` |

The write side of `?T` follows serde rather than LSP: `None` is written as `null`. **Anything that goes out on an LSP wire needs `skipNone`** — the protocol tells an absent key from an explicit `null`, and 477 of the metaModel's properties are optional-only. `?Nullable<T>` is the only shape that keeps the two apart on read whatever the marker says.

**Read-side caveat:** `DataModelStruct.get(key)` returns `DataModelNull` for an *absent* key, collapsing `undefined` and explicit `null`. Use the presence-aware `DataModelStruct.getOrNone` extension (`modules/stdxx/src/data_model.cj`) whenever the distinction matters — `Body.deserialize` depends on it to tell a notification (no `id`) from a response with a null `id`.

It is carried by a `DataModelFields` interface rather than a bare `extend`, because Cangjie exports a direct `extend` only to the package that declares it — an extension meant to cross a package boundary needs an interface to travel with, and `import stdxx.*` then brings it along. Any further `DataModel` helper that the layers above need should be added the same way.

### `cjls` — entrypoint, handlers, and the framework they run in

`main.cj` initializes the global logger and returns what `runServer()` (`run_server.cj`) returns: it serves stdio through `serveLsp(transport, routes())` and exits with the code the protocol asks for — `0` only for an `exit` after a `shutdown`. Stdin is `StdinStream` (`stdin.cj`), `read(2)` on fd 0 through FFI — **never `std.env.getStdIn()`**: its `read` returns only when the buffer is full or at EOF (even a one-byte buffer stalls), so the server would sit on a request an editor already sent. No unit test sees that — they run on `FakeTransport` — which is what the editor smoke tests are for. POSIX only for now; Windows needs a `ReadFile` branch. Logging (`logging.cj`) sets a global `stdx.log` `SimpleLogger` on stderr, its level from the `CJLS_LOG_LEVEL` env var (default `INFO`); log through `getGlobalLogger()`, never print — stdout is the LSP wire.

**Handlers take a context and return the result, registered the way axum does it — no macros:**

```cangjie
func handleInitialize(ctx: Context<InitializeParams>): InitializeResult { ... }

Routes()
    .state(Database())
    .route(InitializeRequestSpec(), handleInitialize)
    .readonly(HoverRequestSpec()) { ctx => hoverAt(ctx.db, ctx.params) }   // ctx.params: HoverParams, inferred
```

- **The spec value carries the types.** `route<P, R>(spec: LspInboundRequest<P, R>, handler: (Context<P>) -> R)` infers `P` and `R` from the spec, so a lambda's `ctx` needs no annotation, and a handler of the wrong params or result fails to compile with a readable unsolvable-constraint error (`InitializeParams <: P, P <: CancelParams`). `route<S>` with only the spec as a type argument is not an option: Cangjie takes all of a function's type arguments or none. Returning the result, rather than writing it into the context, makes a missing or mistyped answer a compile error too.
- **The context is the whole interface** (`server/context.cj`): `params`, `db`, `client`, `cancellation` (jsonrpc's `CancellationToken`; never cancelled for a notification). There is no injection — a handler reads what it needs off `ctx`, as rust-analyzer's handlers read their snapshot.
- **`route` vs `readonly`** (`server/routes.cj`) is how a handler runs, and the context type says which: `route` hands a `Context<P>` with the `Database`, on the read loop, in arrival order — how inputs change; `readonly` hands a `ReadOnlyContext<P>` with a `DatabaseSnapshot` taken on the read loop when the message arrived, on its own `spawn`. A handler written for one does not compile under the other. Routes has just these four methods — request or notification, times the two modes. `Database` is a placeholder for the query database, already split the way it will be; `.state(...)` supplies it.
- **Registration is explicit**, one line per handler, as in rust-analyzer; `Routes` refuses a second handler for a method, and `readonly` for `initialize`, `shutdown` or `exit`, since whatever follows them must see the state they leave. Per-route options, when they come (latency-sensitive, retry on modification), belong in named parameters with defaults.

**The router** (`server/router.cj`, internal) is the `Handler` `jsonrpc` calls. It keeps the lifecycle by method alone — the same for every server: before a successful `initialize` requests get `SERVER_NOT_INITIALIZED` and notifications are dropped; a second `initialize` or anything after `shutdown` is `INVALID_REQUEST`; `exit` runs its handler if any, then closes the connection in any state. The lifecycle messages are otherwise ordinary handlers (`lifecycle.cj`).

### Macro-package mechanics

The one macro package is `stdxx.deriving`, using `std.ast.*`. Generated code is emitted as `quote(...)` templates with `$`-interpolation — the output must be valid Cangjie against the target interfaces, and names them unqualified, so the using package imports what it refers to. A macro package compiles even when the code it *emits* would not, so a green build of the macro package is no evidence the codegen is correct — a build of a package *using* it is. Don't have a macro emit new top-level declarations that need initializing: the order packages are initialized in is not defined.

## Testing conventions

Tests live beside the code as `*_test.cj` in the same package, using `std.unittest` (`@Test` class / `@TestCase` func, `@Expect`/`@Assert`/`@AssertThrows`, `@Configure[randomSeed:]` + `@TestCase[x in random()]` for property tests). Cases follow an `// arrange` / `// act` / `// assert` layout, and are named as sentences describing the behaviour (`closeWakesACallerWaitingForAnAnswer`).

Concurrency is tested deterministically, never with sleeps: `connection_test.cj` drives a `FakeTransport` whose queues let a test block until the connection actually writes, and hands the handler a lambda that parks on a `LinkedBlockingQueue` until the test releases it. Follow that pattern instead of timing assumptions.
