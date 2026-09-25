# ADR-0010: Syntax kinds and typed views are generated from an ungrammar

Status: accepted, 2026-09-25

## Context

`SyntaxKind` was one enum and four hand-written tables (`toString`, `fixedText`, `keyword`, `isKeyword`) that a new kind had to reach, plus the lexer's own punctuation table. A typed AST over `ginkgo` trees would add hundreds of one-line accessors. rust-analyzer generates both (`sourcegen`: `KINDS_SRC` and `rust.ungram`); a Cangjie macro could only see the enum, not the grammar.

## Decision

- `modules/cjsyntax/syntax_kinds.toml` lists the tokens by section; `modules/cjsyntax/cangjie.ungram` gives the shape of every node. `syntax_codegen` makes `SyntaxKind` with its methods, the lexer's table, and `cjsyntax.ast`: a struct per node, an enum per rule listing nodes.
- The output is checked in and goes through `cjfmt`; a test fails when it is not what the generator makes.
- An accessor finds a child by its position among those that could be taken for it; what a position cannot tell is hand-written in `src/ast/node_ext.cj`.
- The generator depends on `cjtoml` and `stdxx` only; `cjsyntax` is a test dependency.
- The kind stays an enum, not a `UInt16`: alignment makes a node no smaller.

## Consequences

- A token or node is one line in one of the two files.
- The ungrammar is tested against the parser (`ConformanceTest`): every file of the repository exactly, a corpus when `CJSYNTAX_CORPUS` names one.
- Views live in `cjsyntax.ast`, apart from `SyntaxKind`, whose constructors would hide the structs of their names.
