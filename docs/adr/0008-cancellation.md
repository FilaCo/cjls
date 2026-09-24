# ADR-0008: Two cancellations, two answers

Status: accepted, 2026-09-24

## Context

- A write must not wait for stale queries, and their answers are wrong anyway.
- `$/cancelRequest` sets the request's `CancellationToken`, which calca did not see: a cancelled query ran to the end.
- calca must not depend on jsonrpc.

## Decision

- calca: `snapshot(cancelledBy: () -> Bool)`; every operation of that handle checks it and throws `Cancelled`.
- The server passes `{=> token.isCancelled}` when it takes a request's snapshot.
- On `Cancelled`: token set → `RequestCancelled`, else → `ContentModified`.

## Consequences

- A cancelled request stops at its next calca call.
- A long computation of one's own calls `db.unwindIfCancelled()`.
- Handlers never catch `Cancelled` (S5).
