# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`cjls` is a Language Server Protocol implementation for the **Cangjie** language, written in Cangjie itself. It is an early-stage MVP, and the work has proceeded bottom-up: the `jsonrpc` transport/peer layer is built and covered by tests, while the LSP layer above it is largely still to be written — `modules/cjls/src/run_server.cj` is a stub with the old server loop commented out, the protocol types are generated from `metaModel.json` except for the messages themselves (enumerations, structures, unions and aliases are; the per-request/notification specs are not yet), and the handler-registration macros are partly stubs.

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

### Commits

Conventional Commits are enforced by commitlint via a husky `commit-msg` hook. Use `type(scope): subject` (e.g. `feat(jsonrpc): ...`); commitizen (`cz-conventional-changelog`) is configured.

## Workspace layout

Five members declared in the root `cjpm.toml`, each its own package:

- **`modules/stdxx`** (`static`) — foundation library: the sum types the protocol needs (`IntegerOrString`, `ArrayOrObject`, `Nullable`), `AnyValue` (a serializable `DataModel`, which `LSPAny` aliases — an imported type can't be extended with an imported interface, so `DataModel` itself never can be), the `DataModel` helpers that go with them (`data_model.cj`), their exceptions (`exception.cj`), plus a `deriving` **macro package** for `@DeriveExt[...]` codegen. No project dependencies.
- **`modules/jsonrpc`** (`static`) — the JSON-RPC peer: model, codec, framed transport, `Connection`. Knows **zero method names**. Depends on `stdxx`.
- **`modules/cjls`** (`executable`) — the server: entrypoint, logging, and the `cjls.macros` macro package for handler registration. Depends on `jsonrpc`.
- **`modules/cjtoml`** (`static`) — a vendored TOML parser/encoder (Huawei, Apache-2.0 with Runtime Library Exception), carried in-tree because `stdx` ships no TOML module. Its public entry point is `unmarshal<T>(path: String): T where T <: Serializable<T>` — it takes a **file path**, not TOML text. Third-party code: keep it byte-identical to upstream, and never run `cjfmt` over it.
- **`modules/lsp_codegen`** (`executable`) — the generator that turns `modules/lsp_codegen/metaModel.json` into typed LSP declarations in `modules/cjls/src/lsp_types` (generated, checked in, never hand-edited — regenerate instead; delete the old files first, the generator does not prune). It takes the meta model path on the command line and everything else from a TOML config passed with `-c`/`--config` (`modules/cjls/lsp_codegen.toml`): `cjpm run --name lsp_codegen -- modules/lsp_codegen/metaModel.json -c modules/cjls/lsp_codegen.toml`. The config declares only `output-subpackage`; the output directory and the root package name are inherited from the `cjpm.toml` next to it (`src-dir`, defaulting to `src`, and `[package] name`), because cjpm requires every subpackage to be named `<package name>.<path under src-dir>`. A relative `src-dir` resolves against the config file's own directory, not the cwd.

  What it emits, and why:
  - **Structures** are flattened — `extends` then `mixins` then own properties, a redeclared property replacing the inherited one in place — into structs with all-named primary constructor parameters and `@DeriveExtSerializable[skipNone]`. A string-literal property (`kind: 'create'`) becomes the struct's `tag:`/`value:` rather than a field. An anonymous literal type is declared as a struct named `<Owner><Property>`, the owner being the structure that *declares* the property — one inheriting it reuses that type rather than declaring its own. A union of two literals, or an alias of a union holding one, has no name to give them, and the generator refuses it rather than merging them.
  - **Unions** (`or` minus `null`) become untagged enums. The name is the alias defining that union if there is one (the first such alias; later ones become `public type Declaration = Definition`), else the members joined with `Or` in the order first met (`StringOrMarkupContent`, arrays plural: `LocationOrLocations`). Variants are ordered by required-key count, most first, so a struct whose keys are a subset of another's can't answer for it. A `[uinteger, uinteger]` member is a two-payload variant.
  - **Every union variant is `As<Member>`** (`AsBoolean(Bool)`, `AsHoverOptions(HoverOptions)`). Not style: an enum constructor is in scope throughout its package *unqualified*, so a variant named `HoverOptions` makes `HoverOptions` a constructor everywhere in `lsp_types` and the struct no type at all — and qualifying the payload type with the package doesn't get past it. The same scoping is why an optional field of `TextDocumentSyncKind` (which has a `None` variant) defaults to `Option<TextDocumentSyncKind>.None`.
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
