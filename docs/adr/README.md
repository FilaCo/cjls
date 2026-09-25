# ADR

One decision per file, ≤ 1 page. An accepted ADR is not rewritten: a new one replaces it, saying "supersedes ADR-NNNN". In discussion `D7` ≡ `ADR-0007`.

Template:

```md
# ADR-NNNN: <decision>

Status: proposed | accepted | superseded by ADR-NNNN, <date>

## Context
## Decision
## Consequences
```

| # | Decision | Status |
|---|---|---|
| [0001](0001-files-are-ropes.md) | Files are persistent ropes; lines break at `\n` | accepted |
| [0002](0002-vfs.md) | A VFS of `FileId`s and folded changes, as rust-analyzer's | accepted |
| [0003](0003-modules-and-packages.md) | A module is a library that knows nothing of the server | accepted |
| [0004](0004-one-database-class.md) | One database class, no interface ladder | accepted |
| [0005](0005-loupe-knows-no-lsp.md) | The analysis API knows no LSP; handlers translate | accepted |
| [0006](0006-handlers-are-not-queries.md) | Handlers are not queries; queries are keyed by entities | accepted |
| [0007](0007-position-encoding.md) | UTF-8 columns when the client offers them | accepted |
| [0008](0008-cancellation.md) | Two cancellations, two answers | accepted |
| [0009](0009-names-of-state-and-database.md) | `ServerState` holds the `AnalysisDatabase`; only calca says `Database` | accepted |
| [0010](0010-generated-syntax.md) | Syntax kinds and typed views are generated from an ungrammar | accepted |
