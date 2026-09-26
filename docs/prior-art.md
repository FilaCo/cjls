# Prior art

The language servers cjls is measured against, in two roles ([D15](adr/0015-reference-implementations.md)): **references**, which cjls learns from, and **competitors**, which a user picks cjls over or not. R4 is both. Where each part of cjls comes from, and where it stands against the competitors. Cite them by id: "as R1 does". Facts as of 2026-09; a row that goes stale is updated, not kept.

## References

| # | Server | Serves | Written in | For cjls |
|---|---|---|---|---|
| R1 | [rust-analyzer](https://github.com/rust-lang/rust-analyzer) | Rust | Rust | **the model**: layers, VFS, main loop, trees, parser, macros, name resolution, API, handlers, tests, LSP extensions |
| R2 | [ty](https://github.com/astral-sh/ty) (server in [ruff](https://github.com/astral-sh/ruff)) | Python | Rust | salsa's current API used natively (tracked structs, interned values, LRU, cycles), where R1 keeps its old query groups through a shim; the model for calca is salsa itself (D15) |
| R3 | [cjc](https://gitcode.com/Cangjie/cangjie_compiler) (`src/Parse`, `src/Sema`) | Cangjie | C++ | **the specification**: what the language is; where cjls disagrees, cjls is wrong |
| R4 | [LSPServer](https://gitcode.com/Cangjie/cangjie_tools) (`cangjie-language-server`, in the SDK as `tools/bin/LSPServer`) | Cangjie | C++ | **the baseline**: the features to reach, behaviour to compare against; not a model |
| R5 | [gopls](https://github.com/golang/tools/tree/master/gopls) | Go | Go | the workspace: a project model from the build tool, snapshots, watched files, a cache on disk |
| R6 | [Roslyn](https://github.com/dotnet/roslyn) | C#, VB | C# | red-green trees (where rowan comes from); overload resolution; immutable workspace snapshots |
| R7 | [Kotlin Analysis API](https://github.com/JetBrains/kotlin/tree/master/analysis) ([kotlin-lsp](https://github.com/Kotlin/kotlin-lsp)) | Kotlin | Kotlin | the nearest language: classes and interfaces, extensions, overloading, named arguments, properties; resolve on demand |
| R8 | [clangd](https://github.com/llvm/llvm-project/tree/main/clang-tools-extra/clangd) | C, C++ | C++ | the shape R4 has: a compiler in-process, a worker per file, a background index |

Looked at, not references:

| Server | Why not |
|---|---|
| [tsgo](https://github.com/microsoft/typescript-go) (TypeScript 7, `tsc --lsp`) | a compiler port: a whole program checked, not queries; pull diagnostics only, which some clients never ask for |
| [Pyright](https://github.com/microsoft/pyright) | lazy checker with hand-made caches, emptied by heap size; R2 covers Python with salsa |
| [sourcekit-lsp](https://github.com/swiftlang/sourcekit-lsp) | Swift is as near to Cangjie as Kotlin, but the server is a wrapper over the compiler (`sourcekitd`) and a build's index store, as R4 is over cjc |
| [HLS / ghcide](https://github.com/haskell/haskell-language-server) | incrementality from a build system (Shake), not from queries |
| [cjlsp](https://github.com/XYZboom/cjlsp) | Cangjie in Rust, own lexer/parser/sema, written in three days (2026-08-28..30) to pass `cangjie_test`'s LSP cases, then paused: a test of a hypothesis, not a product. Worth reading for the macro ABI (`docs/windows-macros.md`, Q9) and the std sources it downloads (Q11) |

## Comparison

| | cjls | R1 rust-analyzer | R2 ty | R4 LSPServer | R5 gopls | R6 Roslyn | R7 Kotlin | R8 clangd | R9 lin-qingying |
|---|---|---|---|---|---|---|---|---|---|
| Frontend | own (`cjsyntax`, `loupe`) | own (`hir`), not rustc | own (ruff's parser, `ty_python_semantic`) | cjc in-process (`libcangjie-lsp`: parser, Sema, CHIR) | `go/parser` + `go/types` | the compiler itself | K2 (FIR) behind the Analysis API | clang in-process | own, K2 ported to Cangjie: PSI → Raw CFIR → lazy resolve phases per declaration |
| Tree | lossless CST (`ginkgo`, rowan) | lossless CST (rowan) | AST with ranges, tokens kept aside | the compiler's AST | AST, comments aside | lossless red-green | lossless PSI | the compiler's AST | lossless PSI (IntelliJ core) |
| Incrementality | queries (calca, salsa's model) | queries (salsa) | queries (salsa, fine-grained: per scope, per definition) | the compiler's pipeline over the package (it links cjc's `IncrementalCompilation`; how much it reuses is not checked) | per package, keyed, export data cached on disk | immutable snapshots, lazy compilations, incremental reparse | PSI modification trackers, lazy resolve phases | preamble (headers) kept, the main file reparsed | a PSI snapshot per open document; the analysis session invalidated on a change |
| Concurrency | read loop writes; a `spawn` per `readonly` request on a snapshot | main loop writes; a pool reads snapshots | same as R1 | a worker per file (`ArkASTWorker`) | a snapshot per change | snapshots, async | read/write actions | a worker per file (`ASTWorker`) | one worker thread, every request in turn |
| Cancellation | a write cancels in-flight queries (D8) | same (salsa) | same (salsa) | not checked | context per snapshot | cancellation tokens | read action restarted | per request | none: a queued request runs |
| Project model | none yet (#12) | `cargo metadata` → crate graph | `pyproject.toml` / `ty.toml`, search paths | `cjpm.toml` (`CompilerCangjieProject`) | `go list` (`go/packages`) | MSBuild | Gradle / Maven import | `compile_commands.json` | a module per workspace folder; `cjpm.toml` not read |
| Macros | none yet (Q9) | `macro_rules!` expanded by its own code; proc macros in a separate process (`proc-macro-srv`) running the compiled dylibs | — | a separate process (`LSPMacroServer`) | — | source generators, in-process | compiler plugins | the preprocessor, in the compiler | R4's `LSPMacroServer` as a child process, flatbuffers over pipes |
| Cache between sessions | none (Q12) | none: every start analyzes again ([#4712](https://github.com/rust-lang/rust-analyzer/issues/4712), open since 2020) | none ([ty#471](https://github.com/astral-sh/ty/issues/471)) | its index | export data and xrefs per package | its index | IntelliJ's indexes | its background index | not checked |
| Index | none | in memory, per crate (fst) | none | background index on disk (SQLite, flatbuffers) | file cache on disk | SQLite on disk | IntelliJ stub indexes on disk | in memory for open files, background on disk | IntelliJ stubs |
| Diagnostics | none yet (#17) | pull for its own, push for `cargo check`'s on save | pull, push for clients without it | push, the compiler's | push | pull | — | push | push (pull written, off by default) |

## Where each part of cjls comes from

| Area | After | What | In cjls |
|---|---|---|---|
| Layers, API without LSP, handlers translate | R1 | `ide` / `rust-analyzer` crates split | D5, D6, S3 |
| VFS, file ids, folded changes | R1 | `vfs` | D2 |
| Lossless trees | R1 ← R6 | rowan | `ginkgo` |
| Parser, events, typed views from an ungrammar | R1 | `parser`, `syntax`, `sourcegen` | `ginkgo.parsing`, `cjsyntax`, D10 |
| What the grammar accepts | R3 | `src/Parse` | the parser test harness (CLAUDE.md) |
| Incremental engine | salsa, R2 | salsa's current API; R2 uses it natively, R1 through `query-group-macro` | `calca`; what is missing: #13, #14 |
| Cancellation on write | R1 | salsa's `Cancelled` | D8 |
| Diagnostics delivery | R1, R2 | pull, push only for clients without it | #17 |
| Semantic tokens | R1 | `syntax_highlighting` over the tree, refined by `hir` | #16 |
| Workspace, watched files | R1, R5 | `project_model`, `load-cargo`; `go/packages`, file watching | #12 |
| Project model | R4, R5 | cjpm has no `cargo metadata` / `go list`: read `cjpm.toml` ourselves, as R4 does | #12, #14 §3 |
| Name resolution | R1 | `ItemTree` (a file's items, stable under edits in bodies) → `DefMap` | Q10 |
| Types, overloads, class hierarchies, `extend` | R3, R6, R7 | R1 has no overloading and no subclassing: Roslyn's and K2's overload resolution, cjc's Sema as the specification | Q10 |
| Macros | R1, R4 | expand out of process, by running the compiled macro package | Q9 |
| Workspace symbols, references | R6, R7, R8 | R1 searches the text, then resolves; the others keep an index. In memory first; on disk only when measured to be needed | #12, Q12 |
| LSP extensions | R1 | `lsp-extensions.md`: methods of its own where LSP has none, under a prefix, in `experimental` | D15 |
| Test fixtures | R1 | `$0` cursors, `//- /path` multi-file fixtures | not yet |

## Competitors

What a user can run instead of cjls, as of 2026-09.

| | R4 LSPServer | R9 lin-qingying/cangjie | cjls |
|---|---|---|---|
| What | the SDK's server, cjc linked in | a frontend of its own after R7, and a standalone server (lsp4j) | a frontend of its own after R1 |
| Getting it | comes with the SDK (`tools/bin/LSPServer`) | no releases: built from source (JDK 21, Gradle, IntelliJ's core) | one binary per platform, GitHub releases (D11) |
| Runs | native; needs the SDK beside it (`@loader_path/../lib/libcangjie-lsp.dylib`, 62 MB) | on the JVM, `-Xmx2g` by default | native, static, nothing beside it |
| Clients | DevEco Studio, its VS Code extension | IntelliJ (LSP4IJ), DevEco Studio; any client over stdio | any client; configs for Neovim, VS Code, Zed (`editors/`) |
| State | released with each SDK | one author, active; `main-tests` red on every run since 2026-08 at least, `:compiler:frontend` not compiling on 2026-09-22 | early: document symbols only |
| Tried (2026-09-26, Neovim 0.12, a two-file project with `extend`) | refuses `initialize` without its extension's `initializationOptions`; with a guessed set: document symbols with signatures, hover, definition, completion, tokens and diagnostics empty, 480 MB — not configured right, so not judged | `cfc565d` builds only with three workarounds (Gradle on JDK 21; `flatc` fetched by hand, its macOS asset name is wrong; duplicate jars in `installDist`), 305 MB installed. `initialize` 0.3–2.7 s, 240–280 MB. Document symbols, semantic tokens, completion (the names in scope, not `c.`'s members) answer; hover and definition fail (`Extend declaration package is not indexed`: `extend` in the file or in `std`); no diagnostics, not even a syntax error | `initialize` 0.2 s, 13 MB; document symbols, nothing else yet |

Features:

| Feature | R4 | R9 | cjls |
|---|---|---|---|
| Diagnostics | the compiler's, all of them; push | its checkers; push | none; syntax in #17, semantic after Q10 |
| Semantic tokens | `full` | `full`, `range` | #16 (syntactic; `full` and `range`) |
| Document symbols | yes | yes | yes |
| Workspace symbols | yes | yes | #12 |
| Hover, definition, references, document highlight, rename | yes | yes | after Q10 |
| Completion, signature help | yes | yes | after Q10 |
| Type definition, implementation | — | yes | after Q10 |
| Call and type hierarchy | yes | — | after Q10 |
| Folding, selection range, formatting | — | yes | — |
| Code actions, code lens, document links | yes | code actions | — |
| Macros | expanded (`LSPMacroServer`) | expanded (R4's `LSPMacroServer`) | Q9 |
| `std` and dependencies | cjc's `.cjo` | `.cjo`, read as flatbuffers | Q11 |
| Extensions of its own (`crossLanguageDefinition`, `extendPublishDiagnostics`, `breakpoints`, …) | for DevEco Studio, in place of standard ones | — | only where LSP has nothing, under `cjls/` (D15) |

R4's column is the methods its binary answers (its strings, SDK of 2025-07); R9's is what its `AnalysisApiCangjieAnalysisFacade` declares, not what worked when tried (above).

Where cjls can be ahead before it has the semantics:

| | R4 | R9 | cjls |
|---|---|---|---|
| A file that does not parse | the compiler's recovery | PSI's recovery | a tree covering the text, always; no false errors against R3 |
| An edit | the compiler's pipeline over the package | the analysis session invalidated | the queries that read what changed |
| Concurrency | a worker per file | one thread for every request | snapshots, cancelled by a write (D8) |
| Distribution | the SDK | a JVM application built from source | one static binary |
