# ADR-0014: rust-analyzer is the model, cjc the specification, LSPServer the baseline

Status: accepted, 2026-09-26

## Context

cjls has followed rust-analyzer piece by piece (D2, D5, D6, D10) and the compiler for the grammar, but nowhere said so, nor whom to follow where rust-analyzer has nothing to offer: Rust has no overloading and no class hierarchies, both central to Cangjie. Cangjie already has a language server, the SDK's `LSPServer` (R4), built on the compiler; [prior-art.md](../prior-art.md) compares it and the others.

## Decision

- **R1 rust-analyzer is the model** for the architecture: layers, VFS, main loop, trees, parser, API, handlers, tests. A departure from it is an ADR saying why.
- **R2 ty is the model for calca**: salsa as it is now, which R1 uses too, but R2 was built on from the start (tracked structs, interned GC); and for what R1 has not caught up on (pull diagnostics).
- **R3 cjc is the specification** of the language: grammar, name resolution, types. Where cjls and cjc disagree, cjls is wrong.
- **R4 LSPServer is the baseline**, not a model: the features to reach, and an oracle to compare behaviour against. cjls does not embed cjc, as R4 does: the compiler checks a package at a time, with no incrementality below one, and is linked into the server (62 MB for `libcangjie-lsp` alone) through C++.
- **Where R1 has no answer** (overloading, subclassing, `extend`), R6 Roslyn and R7 Kotlin's Analysis API show how an IDE frontend resolves them, and R3 says what the answer is.
- Standard LSP only: R4's own methods for DevEco Studio are not followed.

## Consequences

- A design question starts from "what does R1 do", then R2; an ADR names the reference it follows or departs from.
- Semantic analysis (Q10) cannot be copied from R1 alone: its name resolution can, its type inference cannot.
- `prior-art.md` is kept current: a reference that changes what it does is updated there, and an ADR citing the old behaviour stays as it was.
