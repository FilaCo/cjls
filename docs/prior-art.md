# Prior art

The language servers cjls is measured against, what each is for us ([D14](adr/0014-reference-implementations.md)), and where each part of cjls comes from. Cite them by id: "as R1 does". Facts as of 2026-09; a row that goes stale is updated, not kept.

## References

| # | Server | Serves | Written in | For cjls |
|---|---|---|---|---|
| R1 | [rust-analyzer](https://github.com/rust-lang/rust-analyzer) | Rust | Rust | **the model**: layers, VFS, main loop, trees, parser, API, handlers, tests |
| R2 | [ty](https://github.com/astral-sh/ty) (server in [ruff](https://github.com/astral-sh/ruff)) | Python | Rust | calca: salsa as it is now (tracked structs, interned GC, LRU, cycles); pull diagnostics |
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
| [cjlsp](https://github.com/XYZboom/cjlsp) | Cangjie in Rust, own lexer/parser/sema; young, no incremental engine |
| [lin-qingying/cangjie](https://github.com/lin-qingying/cangjie) | Cangjie on the JVM, PSI and an analysis API after R7; young |

## Comparison

| | cjls | R1 rust-analyzer | R2 ty | R4 LSPServer | R5 gopls | R6 Roslyn | R7 Kotlin | R8 clangd |
|---|---|---|---|---|---|---|---|---|
| Frontend | own (`cjsyntax`, `loupe`) | own (`hir`), not rustc | own (ruff's parser, `ty_python_semantic`) | cjc in-process (`libcangjie-lsp`: parser, Sema, CHIR) | `go/parser` + `go/types` | the compiler itself | K2 (FIR) behind the Analysis API | clang in-process |
| Tree | lossless CST (`ginkgo`, rowan) | lossless CST (rowan) | AST with ranges, tokens kept aside | the compiler's AST | AST, comments aside | lossless red-green | lossless PSI | the compiler's AST |
| Incrementality | queries (calca, salsa's model) | queries (salsa) | queries (salsa, fine-grained: per scope, per definition) | the compiler's pipeline over the package (it links cjc's `IncrementalCompilation`; how much it reuses is not checked) | per package, keyed, export data cached on disk | immutable snapshots, lazy compilations, incremental reparse | PSI modification trackers, lazy resolve phases | preamble (headers) kept, the main file reparsed |
| Concurrency | read loop writes; a `spawn` per `readonly` request on a snapshot | main loop writes; a pool reads snapshots | same as R1 | a worker per file (`ArkASTWorker`) | a snapshot per change | snapshots, async | read/write actions | a worker per file (`ASTWorker`) |
| Cancellation | a write cancels in-flight queries (D8) | same (salsa) | same (salsa) | not checked | context per snapshot | cancellation tokens | read action restarted | per request |
| Project model | none yet (#12) | `cargo metadata` → crate graph | `pyproject.toml` / `ty.toml`, search paths | `cjpm.toml` (`CompilerCangjieProject`) | `go list` (`go/packages`) | MSBuild | Gradle / Maven import | `compile_commands.json` |
| Macros | none yet (Q9) | `macro_rules!` expanded by its own code; proc macros in a separate process (`proc-macro-srv`) running the compiled dylibs | — | a separate process (`LSPMacroServer`) | — | source generators, in-process | compiler plugins | the preprocessor, in the compiler |
| Index | none | in memory, per crate (fst) | none | background index on disk (SQLite, flatbuffers) | file cache on disk | SQLite on disk | IntelliJ stub indexes on disk | in memory for open files, background on disk |
| Diagnostics | none yet (#17) | push; `cargo check` on save | pull, push for clients without it | push, the compiler's | push | pull | — | push |

## Where each part of cjls comes from

| Area | After | What | In cjls |
|---|---|---|---|
| Layers, API without LSP, handlers translate | R1 | `ide` / `rust-analyzer` crates split | D5, D6, S3 |
| VFS, file ids, folded changes | R1 | `vfs` | D2 |
| Lossless trees | R1 ← R6 | rowan | `ginkgo` |
| Parser, events, typed views from an ungrammar | R1 | `parser`, `syntax`, `sourcegen` | `ginkgo.parsing`, `cjsyntax`, D10 |
| What the grammar accepts | R3 | `src/Parse` | the parser test harness (CLAUDE.md) |
| Incremental engine | R1, R2 | salsa | `calca`; what is missing: #13, #14 — take salsa's current API, as R2 uses it |
| Cancellation on write | R1 | salsa's `Cancelled` | D8 |
| Diagnostics delivery | R2 | pull, push only for clients without it | #17 |
| Semantic tokens | R1 | `syntax_highlighting` over the tree, refined by `hir` | #16 |
| Workspace, watched files | R1, R5 | `project_model`, `load-cargo`; `go/packages`, file watching | #12 |
| Project model | R4, R5 | cjpm has no `cargo metadata` / `go list`: read `cjpm.toml` ourselves, as R4 does | #12, #14 §3 |
| Name resolution | R1 | `ItemTree` (a file's items, stable under edits in bodies) → `DefMap` | Q10 |
| Types, overloads, class hierarchies, `extend` | R3, R6, R7 | R1 has no overloading and no subclassing: Roslyn's and K2's overload resolution, cjc's Sema as the specification | Q10 |
| Macros | R1, R4 | expand out of process, by running the compiled macro package | Q9 |
| Workspace symbols, references | R1, R8 | an index in memory first; on disk only when measured to be needed | #12 |
| Test fixtures | R1 | `$0` cursors, `//- /path` multi-file fixtures | not yet |

## cjls against R4

The methods R4 answers (its binary's strings, SDK of 2025-07), and where cjls is on them.

| Feature | R4 | cjls |
|---|---|---|
| Diagnostics | the compiler's, all of them; push | none; syntax in #17, semantic after Q10 |
| Semantic tokens | `full` | #16 (syntactic; `full` and `range`) |
| Document symbols | yes | yes |
| Workspace symbols | yes | #12 |
| Hover, definition, references, document highlight, rename | yes | after Q10 |
| Completion, signature help | yes | after Q10 |
| Call and type hierarchy | yes | after Q10 |
| Code actions, code lens, document links | yes | — |
| Macros | expanded (`LSPMacroServer`) | Q9 |
| Extensions of its own (`crossLanguageDefinition`, `extendPublishDiagnostics`, `breakpoints`, …) | for DevEco Studio | never: standard LSP only |

Where cjls can be ahead without the semantics:

| | R4 | cjls |
|---|---|---|
| A file that does not parse | the compiler's recovery | a tree covering the text, always; no false errors against R3 |
| An edit | the compiler's pipeline over the package | the queries that read what changed |
| Clients | DevEco Studio, VS Code | any LSP client; Neovim, VS Code, Zed first |
| Distribution | the SDK (`libcangjie-lsp` alone is 62 MB) | one static binary |
