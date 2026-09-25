# ADR-0009: `ServerState` holds the `AnalysisDatabase`; only calca says `Database`

Status: accepted, 2026-09-25

## Context

Three different things were called a database: calca's interface `Database`, `loupe`'s `RootDatabase` (a root handle or a snapshot, despite the name), and the server's `Database` / `DatabaseSnapshot`, which hold the vfs, the open documents and the encoding besides. A query read `db.analysis`: `db` no database, `analysis` one.

## Decision

| Was | Is |
|---|---|
| `cjls.server.Database` / `DatabaseSnapshot` | `ServerState` / `ServerSnapshot` (rust-analyzer's `GlobalState` / `GlobalStateSnapshot`) |
| `ctx.db`, `Router.withState(db)` | `ctx.state` (`Context`), `ctx.snapshot` (`ReadOnlyContext`), `withState(state)` |
| a handler's `db:` | `state:` / `snap:` |
| `loupe.db.RootDatabase` | `AnalysisDatabase` |
| `calca.Database` | unchanged: the engine's interface |

## Consequences

- `fileStructure(snap.analysis, fileId)` reads as what it is.
- "Database" alone means calca's interface; the analysis's is always `AnalysisDatabase`.
