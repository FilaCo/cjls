# cjls docs

| Where | What | Rule |
|---|---|---|
| [design/](design/) | living rules | tables and lists, no prose; changed in the same PR as the code they describe |
| [adr/](adr/) | decisions taken | one decision per file, ≤ 1 page; never rewritten, superseded by a new one |
| [backlog.md](backlog.md) | open questions | a closed question becomes an ADR or a rule, and leaves the backlog |
| [prior-art.md](prior-art.md) | the servers cjls is measured against, and what comes from which | updated when a reference changes, or a part of cjls starts following one |

How to build, test and commit: [CLAUDE.md](../CLAUDE.md). How to add a handler: [CONTRIBUTING.md](../CONTRIBUTING.md).

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
| D# ≡ ADR-000# | decision | [adr/](adr/) |
| Q# | open question | [backlog.md](backlog.md) |
| R# | reference implementation | [prior-art.md](prior-art.md) |

Ids are never reused; a rule dropped keeps its number, struck through.
