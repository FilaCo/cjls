# ADR-0019: Semantic tokens from the syntax tree first, in a fixed legend of LSP's own types

Status: accepted, 2026-09-26

## Context

- cjls gave an editor no highlighting: a client brought its own grammar or showed plain text. LSP's answer is semantic tokens (`textDocument/semanticTokens/*`).
- Most of what a token is, the tree alone tells: keywords, comments and doc comments, literals, operators, annotations against macro calls, a name at its declaration. Name resolution (Q10) refines one thing only, a name at its use.
- A client knows the token types and modifiers LSP predefines; a custom one needs a theme that knows it, or a fallback the client may not apply.
- `full/delta` answers with the edits since a `resultId`: the server has to keep what it sent, and a `readonly` handler writes nothing (S1, S2), as for `resultId` of diagnostics (Q13).

## Decision

- **Syntactic first.** `loupe.highlight(db, fileId, range)` classifies every token by where it is, then by its kind: a `Name` by what declares it (its `StructureKind`, shared with the outline through `declarationKind`), a `NameRef` only in an annotation, a macro call or a type (`TypeName`, until names resolve). A name at its use, `a.b`, is left out. Inside an `ErrorNode`, by kind alone.
- **What a pattern binds** is a declaration in `let`, `for` and a typed pattern; a lone name in a `case` or a `let` condition may be an enum constructor, and is left out.
- **Modifiers the declaration spells**: `declaration`, `readonly` (`let`, `const`), `static`, `deprecated` (`@Deprecated`); `documentation` for a comment the parser attaches to a declaration; `defaultLibrary` for a primitive type.
- **A plain function**, not a query: the range would be a position in its key (A2). It reads `parse`, which is memoized.
- **A fixed legend of predefined types only**, 19 types and 6 modifiers. A constructor goes as a method, a field as a property, a constant as a `readonly` variable, a primitive type as a `type`; `${`, `}` of an interpolation and other punctuation get no token.
- **`full` and `range`, no `full/delta` and no `refresh`.** A token spanning lines is cut at each line's end unless the client declared `multilineTokenSupport`, which `initialize` keeps in `ServerState` next to the `Encoding`.

## Consequences

- Neovim highlights Cangjie with nothing but the server. VS Code and Zed still need a base grammar (TextMate, tree-sitter), shown before the server answers or when it is not running (Q17).
- Names at their use, `a.b` as a field or a method, `deprecated` at a use: with name resolution and types (Q10), in the same classification, below which nothing changes.
- `refresh` is needed once a file's tokens depend on other files, which is when names resolve; the server already schedules work after a write (D14).
- Every request highlights the whole file, or the range, again: cheap while `parse` is memoized. If it is not, the whole file's highlighting becomes a `@CalcaTracked` over `SourceFile`.
