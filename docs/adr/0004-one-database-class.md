# ADR-0004: One database class, no interface ladder

Status: accepted, 2026-09-24

## Context

rust-analyzer has one database trait per crate because its concrete database, at the top, stores every query. calca keeps every query's state in `Storage`, created lazily per ingredient.

## Decision

- `AnalysisDatabase <: calca.Database` in `loupe.db`, the lowest analysis package.
- Every query, in every layer, takes `AnalysisDatabase` itself.
- Root handle and snapshots are both `AnalysisDatabase` (named in D9).

## Consequences

- No `SourceDatabase`-style interfaces to keep in step.
- An interface appears only with a second implementation.
- A layer needing a new global input cannot add a field to `AnalysisDatabase` from above: needs singleton inputs in calca (Q2).
