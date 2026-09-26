# ADR-0018: calca collects unused interned values, and the memos keyed by them

Status: accepted, 2026-09-27

## Context

Interned values lived as long as their database, and so did every memo key: the calca notes in `CLAUDE.md` said "interned values live as long as their database", and A2 relied on it. Name resolution (Q10) will intern names, and every intermediate `f`, `fo`, `foo` typed in an editor would then stay in the table, with the memos keyed by it, for good. #13 §3–§4 plan how to collect them, after salsa's `#[salsa::interned(revisions = N)]` (D15). Memo values are evicted already (D17). This ADR replaces "interned values live as long as their database" in the calca notes.

## Decision

- **A slab with generations** (`Slab`): a slot holds a value or, vacant, the index of the next vacant one (the free list costs nothing beyond the slots). The free list is LIFO. Removing a value gives its slot the next generation; a slot at the maximum generation is retired and never reused. An `Id` is 32 bits of index and 32 of generation in its one word, so neither `Id` nor `DatabaseKey` grows; an input's row is always of generation 0. `InternTable` is a `Slab` plus a `HashMap` from fields to `Id`.
- **Interning is a dependency** of the query interning, `changedAt` now: the `Id` it gets is not stable across revisions, so a query that interns and returns the `Id` without reading it is computed again once the value is collected. The edge carries the query's own durability so far, not `Low`, or every query that interns would be `Low`; its durability only falls afterwards, so that is conservative. Reading a value records nothing: whoever holds the `Id` got it from interning, or from something that depends on interning.
- **`maybeChangedAfter`** of a value is `true` when the slot's generation is not the `Id`'s; otherwise it marks the value used now. Verifying a memo keeps alive what it interned, whether or not anything executes. `lookup` of a collected `Id` is an `IllegalStateException`.
- **Only `Low` values are collected**: a value's durability is the highest a query interning it had then, `High` outside any query. `verify` skips a memo's edges when nothing of its durability changed, so a `Medium` memo would never notice that a value it interned was gone.
- **Staleness is counted in active revisions**, the revisions the table was used in at all (interned, looked up or verified), a queue of the last `N`: a value is stale once its last use is older than the oldest of them. Each change of a file is a revision (Q6), so counting every revision would collect the names of one file while another is typed in.
- **Collection happens in `newRevision`**, under the write gate with nothing in flight (D17's hook). The candidates are the `Low` values in an `IdLru` of their slots, least recently used first; collection stops at the first one that is not stale, so there is no walk of the table per keystroke.
- **`@CalcaInterned[revisions: N]`**, 3 by default as in salsa; `@CalcaInterned[forever]` keeps every value and records no dependency on interning. A word rather than a number: a count would need a sentinel (salsa's `usize::MAX`), and `0` would read as "at once".
- **The memos keyed by a collected value are dropped** with it (§4). The generated struct implements `InternedValue` (`calcaKey()`: its table and its `Id`). A macro sees only tokens, so a `MemoTable` finds out at run time: its first key is cast to `InternedValue`, and if it is one, the memo table registers with that interned table, which tells it what it collects. The memo keys are a `Slab` too: a memo that read a dropped memo finds its `Id` stale, and counts it as changed. Memos keyed by anything else are never dropped.
- **Not `IndexSet`/`IndexMap` in calca any more**, which cannot have holes. `calca` no longer depends on `index_map`. Measured (`LruFetchBench`, `-O2`, darwin arm64): a fetch that hits takes 132 µs per 4096 against 157 µs on `IndexMap`, whose calls across the module boundary are not inlined (#28).

## Consequences

- A value interned by a `Low` query and unused for 3 active revisions of its table goes, and so do the memos keyed by it, whose slots the next keys reuse.
- A query that interns has `changedAt` now whenever it executes; backdating still applies to its value.
- An `Id` held outside any query (by a handler) may be collected between two requests; reading it then throws. Handlers get `Id`s from queries within the request.
- Memo keys that are not interned values still live as long as the database, and so do inputs (A5).
