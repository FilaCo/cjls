# Analysis

## Pieces

| Piece | Where | Is |
|---|---|---|
| `Rope` | `rope` | immutable UTF-8 text, B-tree of chunks; edits share the rest (D1) |
| `Vfs` | `loupe.vfs` | `FileId → ?Rope` + changes folded until `takeChanges` (D2) |
| `PathInterner` | `loupe.vfs` | `FileId` = the path's index in the order seen, for good; two `ConcurrentHashMap`s, a `Mutex` only to give an id (C9); the only thread-safe part |
| `SourceFile` | `loupe.db` | `@CalcaInput { fileId, text: Rope }`, one per `FileId`, never dropped |
| `AnalysisDatabase` | `loupe.db` | the database; root handle or snapshot (D4, D9) |
| `parse` | `loupe.syntax` | `@CalcaTracked[lru: 128]`, backdated (`Parse` is `Equatable`); keeps the trees of the 128 files parsed last (D17) |
| `SyntaxNodePtr`, `AstPtr` | `ginkgo` | a node as its kind and range, resolved against a root: what a result keeps of a tree (A13) |
| `fileStructure` | `loupe` | API: the outline of a file |
| `diagnostics` | `loupe` | API: a file's `Diagnostic`s (`range: TextRange`, `severity: Severity`, `message`), in the order of the text; for now the lexer's and parser's errors, read from `Parse.errors` and worded by `cjsyntax.message` (D14). Not a query: it collects what queries remember |

## Rules

| # | Rule |
|---|---|
| A1 | Every query takes `AnalysisDatabase` itself; no database interface (D4). |
| A2 | A query is keyed by an entity (`SourceFile`, interned ids), never by a position (D6): memo values are evicted (`lru`, D17), and interned values unused for a while are collected with the memos keyed by them (D18), but other keys live as long as the database. |
| A3 | Position-dependent API (`hover(db, position)`) is a plain function over queries. |
| A4 | Inputs are created and set on the root handle only, outside queries (`IllegalStateException` otherwise). |
| A5 | A deleted file is an empty text; its `FileId` and `SourceFile` stay. |
| A6 | Offsets are UTF-8 bytes on character boundaries, as `TextRange` and `Rope`. |
| A7 | Lines break at `\n` only, as the compiler's lexer; a line ends before the `\r` of `\r\n` (D1). |
| A8 | `loupe` knows no LSP: no URIs, `Position`, encodings or LSP types (D5). |
| A9 | Anything that interns (dense ids in first-seen order) is an `IndexSet`, unless its values are collected: then a `Slab` of generations (calca's interned values and memo keys, D18), or shared between threads: then two `ConcurrentHashMap`s, value → id and id → value, a `Mutex` only to give an id (`PathInterner`, C9; its `FileId`s are forever, A5). |
| A10 | A value a query returns is `Equatable`, so it backdates; `[noEq]` only with a reason. |
| A11 | Diagnostics are part of the results of the queries that find them (`Parse.errors`), never accumulated on the side (D14). |
| A12 | A diagnostic's range is what its source gives, an empty one included ("expected `}`" at the end of a file); widening it for a client is translation. |
| A13 | A tracked result holds no `SyntaxNode`, `SyntaxToken`, typed view, `GreenNode` or `Parse` (`parse` itself excepted), only `SyntaxNodePtr`/`AstPtr`: a node keeps its whole tree alive, and `lru` on `parse` frees nothing (D17). A handler holds nodes for the length of a request. |
