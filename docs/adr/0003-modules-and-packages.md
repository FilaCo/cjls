# ADR-0003: A module is a library that knows nothing of the server

Status: accepted, 2026-09-24

## Context

- A package is Cangjie's unit of compilation; rust-analyzer's crates map to packages, not modules.
- Nothing can depend on an executable module.
- The analysis must not see LSP types, and only a module boundary makes the compiler check that.

## Decision

- Module: a library knowing nothing of the server (`stdxx`, `jsonrpc`, `index_map`, `linked_list`, `calca`, `ginkgo`, `rope`, `cjsyntax`, `loupe`, `cjtoml`).
- Everything only the server has: a package of `cjls`.

## Consequences

- `loupe` holds the whole analysis (`vfs`, `db`, queries, API); `cjls` holds the server, handlers, `lsp_types`.
- A second consumer of the analysis (a CLI) needs no move.
