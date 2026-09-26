# cjls docs

| Where | What | Rule |
|---|---|---|
| [design/](design/) | living rules | tables and lists, no prose; changed in the same PR as the code they describe |
| [adr/](adr/) | decisions taken | one decision per file, ≤ 1 page; never rewritten, superseded by a new one |
| [backlog.md](backlog.md) | open questions | a closed question becomes an ADR or a rule, and leaves the backlog |
| [prior-art.md](prior-art.md) | the servers cjls is measured against, and what comes from which | updated when a reference changes, or a part of cjls starts following one |

How to build, test and commit: [CLAUDE.md](../CLAUDE.md). How to add a handler: [CONTRIBUTING.md](../CONTRIBUTING.md).

## When a change writes here

Only when it tells the next reader something the docs and the code do not already say. A change that follows the rules written here writes nothing: a new read request along the slice (S1–S6), a new API function of `loupe`, a new query keyed by an entity.

| Writes | When |
|---|---|
| a rule (`design/`) | the change sets a constraint future code must keep, and the compiler does not check it |
| an ADR | there was a real choice: alternatives weighed, one taken, a reason that is not obvious from the code — or a departure from a rule, R1 or R3 |
| a question (`backlog.md`) | something is knowingly left undone, and the way to do it is open |
| nothing | the list of what exists (requests served, API functions, fields): that is the code (`handlers/router.cj`, `loupe`'s package) |
| nothing | the story of the PR, its measurements included: the PR description, with the `@Bench` left beside the code; a rule or ADR cites the conclusion and the bench's name |

One fact, one place: a rule is stated once, in `design/`; an ADR says why, CLAUDE.md and CONTRIBUTING.md link to both rather than repeat them.

## Design

| File | Topic |
|---|---|
| [00-layers.md](design/00-layers.md) | modules, packages, what each layer knows |
| [01-request-slice.md](design/01-request-slice.md) | one request / notification from the wire down to the inputs, and back |
| [02-analysis.md](design/02-analysis.md) | the database, queries, files, positions |
| [03-conventions.md](design/03-conventions.md) | how code is written, where the compiler leaves a choice |

## Identifiers

| Prefix | What | Defined in |
|---|---|---|
| L# | layer | [00-layers.md](design/00-layers.md) |
| S# | rule of the request slice | [01-request-slice.md](design/01-request-slice.md) |
| A# | rule of the analysis | [02-analysis.md](design/02-analysis.md) |
| C# | code convention | [03-conventions.md](design/03-conventions.md) |
| D# ≡ ADR-NNNN | decision | [adr/](adr/) |
| Q# | open question | [backlog.md](backlog.md) |
| R# | reference implementation | [prior-art.md](prior-art.md) |

Ids are never reused. A rule dropped keeps its number, struck through; a closed question leaves the backlog, and the ADR or rule that closes it names it.
