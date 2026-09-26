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
