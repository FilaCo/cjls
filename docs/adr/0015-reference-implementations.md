# ADR-0015: rust-analyzer is the model, salsa the model for calca, cjc the specification; LSPServer and lin-qingying/cangjie the competitors

Status: accepted, 2026-09-26

## Context

cjls has followed rust-analyzer piece by piece (D2, D5, D6, D10) and the compiler for the grammar, but nowhere said so, nor whom to follow where rust-analyzer has nothing to offer: Rust has no overloading and no class hierarchies, both central to Cangjie. Cangjie already has language servers a user can pick instead: the SDK's `LSPServer` (R4), built on the compiler, and [lin-qingying/cangjie](https://github.com/lin-qingying/cangjie) (R9), a frontend of its own after Kotlin's K2 with a standalone server on the JVM. [prior-art.md](../prior-art.md) compares them and the others.

ty (R2) is the newer server on salsa, but not a model for the frontend: Python has no macros, no compilation, and a gradual type system; Cangjie, like Rust, has macros expanded before names resolve and a package graph from its build tool. Its server is itself built on R1's `lsp-server` and main loop. What it has that R1 lacks is salsa's current API used natively: R1 runs on the same salsa (0.28), through `query-group-macro`, a shim that keeps its old query groups. Both pull diagnostics (R1 its own, not `cargo check`'s).

## Decision

- **R1 rust-analyzer is the model** for the frontend and the server: layers, VFS, main loop, trees, parser, macros (Q9), name resolution (Q10), API, handlers, tests. A departure from it is an ADR saying why.
- **salsa is the model for calca**: its current API and its book, not R1's database, which keeps the old query groups through a shim. R2 is how that API is used natively (tracked structs, interned values, LRU, cycles).
- **R3 cjc is the specification** of the language: grammar, name resolution, types. Where cjls and cjc disagree, cjls is wrong.
- **Two roles, kept apart**: a *reference* is where cjls learns how; a *competitor* is what a user compares it with. R4 is both.
- **R4 LSPServer is the baseline**, not a model: the features to reach, and an oracle to compare behaviour against. cjls does not embed cjc, as R4 does: the compiler checks a package at a time, with no incrementality below one, and is linked into the server (62 MB for `libcangjie-lsp` alone) through C++.
- **Where R1 has no answer** (overloading, subclassing, `extend`), R6 Roslyn and R7 Kotlin's Analysis API show how an IDE frontend resolves them, and R3 says what the answer is. So for global queries (workspace symbols, references, implementations): R1 has no index and searches the text before resolving; R6 and R7 keep one.
- **Standard LSP first, extensions where LSP has nothing**: what the protocol has is served its way. An extension is a method under `cjls/`, advertised in `experimental` capabilities and documented in `docs/`, as R1's `lsp-extensions.md`; every client works without it. R1 has some 35 (`expandMacro`, `syntaxTree`, `runnables`, …), and several became LSP (inlay hints in 3.17, snippet edits in 3.18). R4's methods for DevEco Studio are not followed: they stand in for standard ones for one client.
- **R9 is a competitor**, not a model: its architecture is R7's, carried to Cangjie, on the JVM and IntelliJ's core. How it maps Cangjie onto K2's resolve phases (a phase for `extend`) is read when Q10 is designed, as R7 is.

## Consequences

- A design question starts from "what does R1 do"; for calca, "what does salsa do"; an ADR names the reference it follows or departs from.
- Semantic analysis (Q10) cannot be copied from R1 alone: its name resolution can, its type inference cannot.
- The index behind #12 is measured against R1's text search before it is built after R6 or R7; a cache on disk is Q12.
- The first candidates for extensions: `cjls/expandMacro` (Q9), `cjls/syntaxTree`, runnables for `@Test`. Each needs code in `editors/`, and its spec written by hand: `lsp_codegen` knows only the metaModel.
- *cjls against its competitors* in `prior-art.md` is what cjls has to beat, feature by feature; it says where cjls can be ahead before it has the semantics.
- `prior-art.md` is kept current: a reference that changes what it does is updated there, and an ADR citing the old behaviour stays as it was.
