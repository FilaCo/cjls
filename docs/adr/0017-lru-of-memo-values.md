# ADR-0017: calca evicts memo values by LRU; a query result keeps pointers, never nodes

Status: accepted, 2026-09-26

## Context

calca forgot nothing: every memo kept its value for as long as the database lived. The trees `parse` keeps for every file ever seen are most of the memory already. #13 plans three ways to forget, after salsa (D15): LRU of memo values, GC of interned values, and dropping the memos keyed by a collected value. Only the first has something to free today: nothing is interned in `loupe` yet, so the other two wait for name resolution (Q3).

## Decision

- **`IdLru`, inside calca**: the keys of one function in the order of last use, a doubly linked list over their `Id`s — `prev`/`next` arrays indexed by `Id.index`, which is dense (the key's index in the memo table). Not thread-safe; `touch` never evicts, only `trim` does. Not a hash set in a module of its own (`LruSet<T>`, the first version): nothing needs hashing when the keys are already dense indices, and a call into another package is not inlined without `@Frozen` (#28). Measured (`IdLruBench`, `LruFetchBench`; `-O2`, darwin arm64): 4096 touches and a trim take 22.5 µs on `IdLru`, 41 µs on the same hash set inside calca, 486 µs on `LruSet` across the module boundary; a fetch that hits costs +1% with `lru` on `IdLru`, +20% on `LruSet`. Nor an `IndexMap`: removing from one is a swap or an O(n) shift. Nor `std.collection.LinkedList`: it cannot move a node, so a touch removes it and allocates another — 4x `IdLru` with its nodes found by `Id.index`, 5.6x through a `HashMap`.
- **The list is `linked_list.IndexLinkedList`**, `IdLru` a wrapper over it, with `ArenaList<T>` beside it for lists of values: a module of its own, `@Frozen` down to the private helpers. From calca a touch costs ~3 ns more than the same list written inside calca (44.9 against 32.3 µs, `IdLruBench`), and nothing measurable on a fetch that hits (162.6 against 162.5 µs, `LruFetchBench`).
- **`@CalcaTracked[lru: N]`** keeps the values of the `N` keys fetched last; capacity at compile time only, as rust-analyzer lives with (R1).
- **A use is a `fetch`**, a hit or an execution, touched under the `MemoTable` lock already taken; verifying a memo for another one's sake is not a use.
- **Eviction happens only when a write opens a revision**, under the gate with nothing in flight (`Ingredient.newRevision`), as salsa does in `new_revision`: no reader ever sees a memo lose its value.
- **An evicted memo keeps its revisions and dependencies**, only the value goes. It is verified by its edges without executing: unchanged, it answers its `changedAt`; changed, it answers "changed" at once, and whoever fetches it computes it (salsa's `maybe_changed_after`).
- **Backdating after eviction**: fetched while its inputs are unchanged, it is computed again and keeps its `changedAt`; after a change there is no old value to compare with, so it counts as changed.
- **`parse` has `lru: 128`.**
- **A tracked result holds no node** (A13): `SyntaxNodePtr`/`AstPtr` in `ginkgo` (R1's), resolved against the root of a `parse` the query calls itself. `toNode` descends through the nodes covering the range and takes the innermost of that kind and range. A test in `loupe` keeps the rule: an evicted tree is freed (a `WeakRef` on its green root cleared), and one a result holds a node of is not.

## Consequences

- Memory for trees is bounded by the 128 files parsed last, whatever the workspace; a file outside them is parsed again when read.
- A query that reads an evicted tree after its file changed runs again even when the tree parses the same: correct, only slower.
- `std.runtime.gc` returns before weak references are cleared; the test waits after it, bounded.
- A2 stands for memo keys and interned values, which still live as long as the database: GC of interned values and of memos keyed by them, run-time capacity and capacity by memory are Q3 and Q16.
