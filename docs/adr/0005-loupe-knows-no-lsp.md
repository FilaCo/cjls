# ADR-0005: The analysis API knows no LSP; handlers translate

Status: accepted, 2026-09-24

## Context

rust-analyzer splits `ide` (pure API) from the server's `from_proto`/`to_proto`. LSP types are generated, heavy, and tied to one protocol.

## Decision

- `loupe` speaks `FileId`, UTF-8 byte offsets, `TextRange` and its own result types.
- `cjls.handlers` translates: `from_proto.cj` (URI → `SourceFile`, `Position` → offset), `to_proto.cj` (offsets → `Range`, loupe kinds → LSP kinds).
- Translation uses the snapshot's rope and the negotiated encoding.

## Consequences

- `loupe` is tested without LSP; a CLI can use it.
- A handler is a few lines; its logic lives and is tested in `loupe`.
