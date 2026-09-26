# Backlog

| # | Question | Notes |
|---|---|---|
| Q1 | Workspace loader | files not open are read from disk only on `didClose`; no watching, no `didChangeWatchedFiles` |
| Q2 | Singleton inputs in calca | a layer above `loupe.db` cannot add a global input (project model) to `AnalysisDatabase` (D4) |
| Q3 | LRU / GC of memos and interned values in calca | until then, A2 |
| Q4 | Server push (`publishDiagnostics`) | who schedules it after a write: the server, not a handler; see [01-request-slice.md](design/01-request-slice.md) |
| ~~Q5~~ | ~~Windows paths in `VfsPath`~~ | closed by [D12](adr/0012-drive-paths.md) |
| Q6 | Batched writes | every file change is its own revision |
| Q7 | `protected` instead of `public` across `cjls` packages | module-wide visibility |
| Q8 | Move the architecture notes of CLAUDE.md into `design/` | jsonrpc, calca, serialization, lsp_codegen |
| Q9 | Macro expansion | Cangjie macros are compiled packages (`lib-macro_<pkg>`, exporting `macroCall_c_<Macro>_<pkg>`, `macroCall_a_…` for attribute macros) run on tokens. Three ways: load them in-process and start the Cangjie runtime (cjlsp: a macro that crashes takes the server down); run R4's `LSPMacroServer` from the SDK as a child process, flatbuffers (`MacroMsgFormat.fbs`) over pipes (R9); a process of our own, as R1's `proc-macro-srv`. The second costs least ([prior-art.md](prior-art.md)) |
| Q10 | Name resolution and types | R1 for resolution (`ItemTree` → `DefMap`), but overloads, subclassing and `extend` have no R1 answer: R6, R7 (and R9, which carries R7 to Cangjie), and R3's Sema as the specification (D15) |
| Q11 | Declarations of `std` and of dependencies | the SDK ships no sources of `std`, only compiled modules and their `.cjo` (`modules/<target>/std/std.*.cjo`), which are flatbuffers (`PackageFormat.fbs`, `ModuleFormat.fbs` in cjc's `schema/`). Read the `.cjo`, as R4 (cjc's `CjoManager`) and R9 do, or parse the sources of the matching version, downloaded (cjlsp). Name resolution (Q10) needs one of them before `String` or `println` resolve |
| Q12 | A cache on disk | every start computes everything again: calca keeps its memos in memory only, as R1 and R2 do (neither has a cache on disk). salsa has a prototype behind a feature (`persistence`, salsa#967, 2025-08: every dependency of a cached query serializable, inputs hard to change after loading); R4, R5 and R8 keep an index or per-package summaries instead. The cheapest part is what only changes with the SDK or a dependency's version — `std`'s declarations (Q11), a dependency's — keyed by that version. Decided once a cold start on a large workspace is measured |
