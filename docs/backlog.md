# Backlog

| # | Question | Notes |
|---|---|---|
| Q1 | Workspace loader | files not open are read from disk only on `didClose`; no watching, no `didChangeWatchedFiles` |
| Q2 | Singleton inputs in calca | a layer above `loupe.db` cannot add a global input (project model) to `AnalysisDatabase` (D4) |
| Q3 | LRU / GC of memos and interned values in calca | until then, A2 |
| ~~Q4~~ | ~~Server push (`publishDiagnostics`)~~ | closed by [D14](adr/0014-diagnostics-pull-first.md) |
| ~~Q5~~ | ~~Windows paths in `VfsPath`~~ | closed by [D12](adr/0012-drive-paths.md) |
| Q6 | Batched writes | every file change is its own revision |
| Q7 | `protected` instead of `public` across `cjls` packages | module-wide visibility |
| Q8 | Move the architecture notes of CLAUDE.md into `design/` | jsonrpc, calca, serialization, lsp_codegen |
| Q9 | `resultId` and `unchanged` diagnostic reports | the server has to keep each document's last result, which a `readonly` handler cannot write (S1, S2); a syntactic report is cheap to send whole |
| Q10 | `workspace/diagnostic` | needs the files that are not open (Q1, #12) |
| Q11 | Validation and semantic diagnostics | the compiler's checks after parsing (modifier conflicts, annotation targets), then name resolution and types; `interFileDependencies: true` then; kept in query results (A11) |
