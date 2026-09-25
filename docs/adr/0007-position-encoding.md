# ADR-0007: UTF-8 columns when the client offers them

Status: accepted, 2026-09-24

## Context

LSP 3.17 lets the server pick from the client's `general.positionEncodings`; UTF-16 is the mandatory default. Text is kept as UTF-8.

## Decision

- `initialize`: UTF-8 if offered, else UTF-16; advertised as `positionEncoding`.
- Stored in `ServerState.encoding`, copied into every snapshot.

## Consequences

- With UTF-8, a column is a byte count: no counting at all.
- Every conversion takes the encoding; tests cover both.
