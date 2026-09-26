# ADR-0014: rust-analyzer is the model, cjc the specification; LSPServer and lin-qingying/cangjie the competitors

Status: accepted, 2026-09-26

## Context

cjls has followed rust-analyzer piece by piece (D2, D5, D6, D10) and the compiler for the grammar, but nowhere said so, nor whom to follow where rust-analyzer has nothing to offer: Rust has no overloading and no class hierarchies, both central to Cangjie. Cangjie already has language servers a user can pick instead: the SDK's `LSPServer` (R4), built on the compiler, and [lin-qingying/cangjie](https://github.com/lin-qingying/cangjie) (R9), a frontend of its own after Kotlin's K2 with a standalone server on the JVM. [prior-art.md](../prior-art.md) compares them and the others.

## Decision

- **R1 rust-analyzer is the model** for the architecture: layers, VFS, main loop, trees, parser, API, handlers, tests. A departure from it is an ADR saying why.
- **R2 ty is the model for calca**: salsa as it is now, which R1 uses too, but R2 was built on from the start (tracked structs, interned GC); and for what R1 has not caught up on (pull diagnostics).
- **R3 cjc is the specification** of the language: grammar, name resolution, types. Where cjls and cjc disagree, cjls is wrong.
- **Two roles, kept apart**: a *reference* is where cjls learns how; a *competitor* is what a user compares it with. R4 is both.
- **R4 LSPServer is the baseline**, not a model: the features to reach, and an oracle to compare behaviour against. cjls does not embed cjc, as R4 does: the compiler checks a package at a time, with no incrementality below one, and is linked into the server (62 MB for `libcangjie-lsp` alone) through C++.
- **Where R1 has no answer** (overloading, subclassing, `extend`), R6 Roslyn and R7 Kotlin's Analysis API show how an IDE frontend resolves them, and R3 says what the answer is.
- **R9 is a competitor**, not a model: its architecture is R7's, carried to Cangjie, on the JVM and IntelliJ's core. How it maps Cangjie onto K2's resolve phases (a phase for `extend`) is read when Q10 is designed, as R7 is.
- Standard LSP only: R4's own methods for DevEco Studio are not followed.

## Consequences

- A design question starts from "what does R1 do", then R2; an ADR names the reference it follows or departs from.
- Semantic analysis (Q10) cannot be copied from R1 alone: its name resolution can, its type inference cannot.
- *cjls against its competitors* in `prior-art.md` is what cjls has to beat, feature by feature; it says where cjls can be ahead before it has the semantics.
- `prior-art.md` is kept current: a reference that changes what it does is updated there, and an ADR citing the old behaviour stays as it was.
