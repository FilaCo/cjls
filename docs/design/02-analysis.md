# Analysis

## Pieces

| Piece | Where | Is |
|---|---|---|
| `Rope` | `rope` | immutable UTF-8 text, B-tree of chunks; edits share the rest (D1) |
| `Vfs` | `loupe.vfs` | `FileId → ?Rope` + changes folded until `takeChanges` (D2) |
| `PathInterner` | `loupe.vfs` | `IndexSet<VfsPath>`: `FileId` = index, for good; the only thread-safe part |
| `SourceFile` | `loupe.db` | `@CalcaInput { fileId, text: Rope }`, one per `FileId`, never dropped |
| `RootDatabase` | `loupe.db` | the database; root handle or snapshot (D4) |
| `parse` | `loupe.syntax` | `@CalcaTracked`, backdated (`Parse` is `Equatable`) |
| `fileStructure` | `loupe` | API: the outline of a file |

## Rules

| # | Rule |
|---|---|
| A1 | Every query takes `RootDatabase` itself; no database interface (D4). |
| A2 | A query is keyed by an entity (`SourceFile`, interned ids), never by a position: calca has no LRU or GC yet, a memo lives forever (D6). |
| A3 | Position-dependent API (`hover(db, position)`) is a plain function over queries. |
| A4 | Inputs are created and set on the root handle only, outside queries (`IllegalStateException` otherwise). |
| A5 | A deleted file is an empty text; its `FileId` and `SourceFile` stay. |
| A6 | Offsets are UTF-8 bytes on character boundaries, as `TextRange` and `Rope`. |
| A7 | Lines break at `\n` only, as the compiler's lexer; a line ends before the `\r` of `\r\n` (D1). |
| A8 | `loupe` knows no LSP: no URIs, `Position`, encodings or LSP types (D5). |
| A9 | Anything that interns (dense ids in first-seen order) is an `IndexSet`. |
| A10 | A value a query returns is `Equatable`, so it backdates; `[noEq]` only with a reason. |
