# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`cjls` is a Language Server Protocol implementation for the **Cangjie** language, written in Cangjie itself. It is an early-stage MVP — significant parts of the server loop are stubbed or commented out (see `modules/cjls/src/run_server.cj`), and the metaprogramming layer that will wire everything together is only partially implemented.

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
- Run a subset of tests: `cjpm test '--filter=MessageSerializeTest.*'` — filter is `<TestClass>.<testCase>`, `*` wildcards allowed. Quote it: the user's shell is fish, which glob-expands an unquoted `*`.

### stdx dependency bootstrap (important)

The project depends on the external `stdx` library via `bin-dependencies` pointing at `third_party/stdx`. That path is **not** checked in — `build.cj` runs as a `pre-build` build script and symlinks `third_party/stdx` from the `CANGJIE_STDX_PATH` environment variable. If a build fails resolving `stdx.*` imports, confirm `CANGJIE_STDX_PATH` is set and `third_party/stdx` exists (currently symlinked to `~/.cangjie/third_party/stdx/static/stdx`).

### Commits

Conventional Commits are enforced by commitlint via a husky `commit-msg` hook. Use `type(scope): subject` (e.g. `feat(cjls): ...`); commitizen (`cz-conventional-changelog`) is configured.

## Workspace layout

Three members declared in the root `cjpm.toml`, each its own package:

- **`modules/stdxx`** (`static`) — foundation library. Its `deriving` **macro package** provides `@DeriveExt[...]` codegen. No project dependencies.
- **`modules/lsp`** (`static`) — transport + protocol types. JSON-RPC framing, message model, and the `LspAny` JSON value type. Depends on `stdxx`.
- **`modules/cjls`** (`executable`) — the server itself: entrypoint, handlers, LSP request/notification types, logging. Depends on `lsp` and `stdxx`.

Dependencies flow one way: `cjls → lsp → stdxx`.

## Architecture

### JSON serialization is macro-derived, not hand-written

Serialization is the backbone everything else builds on. Two macro systems generate it:

- **`@DeriveExt[Json]`** (from `stdxx.deriving`, also `[JsonSerializable]` / `[JsonDeserializable]` individually) generates `extend`s implementing `toJson`/`fromJson`. **Only works on `struct`s that declare a primary constructor**; member params of that ctor become the JSON fields. Key convention enforced by the generated code: an `Option` field **with a default value** is omitted entirely when `None` — `null` is never written for a missing optional. So model "optional in the protocol" as `field!: ?T = None`, and "always present" as a plain `field: T`.
- **`LspAny`** (`modules/lsp/src/lsp_any.cj`) is the dynamic JSON value enum (`LspNull`/`LspBool`/`LspInteger`/`LspString`/`LspArray`/`LspObject`). `toLspAny`/`fromLspAny` convert any `JsonSerializable`/`JsonDeserializable` to/from it by round-tripping through a JSON byte buffer. This is how strongly-typed params (e.g. `InitializeParams`) cross the loosely-typed message boundary.

Note: enums and the `Message` envelope implement `toJson`/`fromJson` **by hand** (see the comment in `message.cj` — deriving on variant types would recurse infinitely). When adding a protocol type, prefer a struct so it can be derived.

### JSON-RPC transport (`modules/lsp`)

`Message` is an enum of `Request(RequestMessage) | Notification(NotificationMessage) | Response(ResponseMessage)`. `Message.read`/`write` (in `message_io.cj`) handle `Content-Length`-framed streams; `Header` (in `header.cj`) parses the framing. `Message.fromJson` distinguishes the three variants structurally (presence of `id`/`method`/`result`/`error`), since JSON-RPC has no discriminator field. `ErrorCode` maps to/from the standard JSON-RPC + LSP integer codes.

### Handler registration via macros (`modules/cjls`)

The intended pattern (partially implemented) for adding an LSP method:

1. Define a class annotated with `@LspRequest["method", params: P, result: R]` (or `@LspNotification[method: "...", params: P]`), containing a `@LspHandle`-annotated static `handle` func.
2. The macro generates an `extend` implementing the `LspRequest<P,R>` / `LspNotification<P>` interface (in `requests/request.cj`, `notifications/notification.cj`), exposing `METHOD` and a uniform `handle(params, ctx: GlobalContext)`. `@LspNotification`'s `buildHandleCall` maps the user's handler params by name: a param named `params` receives the message params, any other name is pulled from `ctx.<name>` (i.e. `GlobalContext` fields).
3. Register the type in the `@LspHandlers[requests: [...], notifications: [...]]` list on `CjlsHandlers` (`cjls_handlers.cj`), which is meant to generate the `dispatchRequest`/`dispatchNotification` router.

Concrete request/notification types live under `modules/cjls/src/requests/` and `modules/cjls/src/notifications/` (`Initialize`, `Shutdown`, `Initialized`, `Exit`, `DidOpenTextDocument`).

**Current state:** `@LspRequest` and `@LspHandlers` macro bodies are still stubs that just return their input (`extendLspRequest` exists but is unused); `@LspNotification` is the most complete. `GlobalContext` and `Documents` (`modules/cjls/src/server/`) are empty shells. Expect to flesh these out rather than assume they work.

### Macro-package mechanics

Macros live in dedicated `macro package` files (`cjls.macros`, `stdxx.deriving`) and use `std.ast.*`. Shared helpers are in `macros/utils.cj` (`lexAttrs` for parsing attribute arguments, `Decl.getGenericFragments()` for propagating generics into generated `extend`s). When editing macros, remember generated code is emitted as `quote(...)` templates with `$`-interpolation — the output must be valid Cangjie against the target interfaces.

### Entrypoint & logging

`main.cj` initializes the global logger then calls `runServer()`, catching `ProtocolStateException` (protocol invariant violations) vs. other exceptions. Logging (`logging.cj`) wraps `stdx.log` with a global `SimpleLogger` to stderr, an `[cjls]` prefix, and level controlled by the `CJLS_LOG_LEVEL` env var (default `INFO`). Use `logInfo`/`logError`/`logDebug`/etc. rather than printing.
