# ADR-0006: Handlers are not queries; queries are keyed by entities

Status: accepted, 2026-09-24

## Context

- Handler params (URI, position, encoding) change with every keystroke: a memo would rarely hit.
- LSP types are neither `Hashable` nor `Equatable`.
- Handlers have effects: `Client`, `Logger`, cancellation.
- calca has no LRU or GC: every memo and interned key lives as long as the database.

## Decision

- Handlers stay plain functions.
- `@CalcaTracked` only for what is keyed by an entity (`parse(file)`, outline, diagnostics per file, later names and types).
- Position-dependent API (`hover(db, position)`) is a plain function over those queries.

## Consequences

- Memo tables grow with the code, not with the requests.
