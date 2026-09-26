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
| [0011](0011-ci-and-releases.md) | A pinned nightly toolchain, CI on three platforms, releases from `cog bump` | accepted |
| [0012](0012-drive-paths.md) | Paths are `std.fs.Path`, URIs are stdx's `URL`; Windows drives are spelled one way | accepted |
| [0013](0013-stdin-is-read-with-readv.md) | Stdin is read with `readv`, not `read`: cjc treats `read` as `@FastNative` | accepted |
| [0014](0014-diagnostics-pull-first.md) | Diagnostics are pulled; pushed, by the server after a write, only to clients that cannot pull | accepted |
| [0015](0015-reference-implementations.md) | rust-analyzer is the model, salsa the model for calca, cjc the specification; LSPServer and lin-qingying/cangjie the competitors | accepted |
| [0016](0016-editor-integrations-are-repositories.md) | Each editor integration is a repository of its own in ide4cj: `cangjie.nvim` for Neovim | accepted |
| [0017](0017-lru-of-memo-values.md) | calca evicts memo values by LRU; a query result keeps pointers, never nodes | accepted |
| [0018](0018-gc-of-interned-values.md) | calca collects unused interned values, and the memos keyed by them | accepted |
| [0019](0019-syntactic-highlighting.md) | Semantic tokens from the syntax tree first, in a fixed legend of LSP's own types | accepted |
| [0020](0020-weekly-releases.md) | A release every week from a green master; the first one by hand, its changelog written; versions of cjls's own | accepted |
