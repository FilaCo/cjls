# ADR-0020: The Linux binary is not linked with LTO

Status: accepted, 2026-09-27

## Context

Since 2026-09-26, CI (D11) linked the Linux binary it tests and ships with `--lto=full`: 9.5 MB against 14.5. The `End-to-end (ubuntu-latest)` job then failed about one run in three, always `test_idle.py`, the server killed by `SIGSEGV` from `gc-main-thread` or a `schd-worker`. It started with pushed diagnostics (D14), which parse files on their own thread after a write, so a collection meets a thread in the parser.

Measured on a Linux x64 host, `test_idle.py` alone, the binary pinned to 4 cores as a runner has:

| binary | nightly | failed |
|---|---|---|
| `--static`, LTO | 20260918 | 6 / 40 |
| `--static`, LTO, stdin read into a buffer of its own | 20260918 | 12 / 60 |
| `--static`, LTO | 20260927 | 17 / 60 |
| `--static` | 20260918 | 0 / 120 |
| `--static` | 20260927 | 0 / 60 |

Every one of 14 core dumps is the same: the collector walks a thread's stack roots (`RegSlotsMap::VisitSingleSlotsRoot`, `RootMap::VisitRegRoots`) and dies in `MapleRuntime::CheckAndPush` on a reference that is no object, the thread stopped at the safepoint in `std.core.Range.init` called from `ginkgo.parsing.Lexed.tokenText` — `text[r.start..r.end]`. The stack map LTO produced for that safepoint is wrong. The stdin buffer pinned across a blocking `readv` (D13) was the first suspect; reading into memory of its own changed nothing, and it was dropped.

## Decision

- No binary is linked with LTO: CI tests and ships the `--static` one from `cjpm build`, on Linux as elsewhere.
- The modules declare no `lto` option any more, so nothing builds bitcode by accident.

## Consequences

- The Linux binary is 14.5 MB (10.9 stripped) again.
- LTO comes back only once a nightly passes `test_idle.py` a few hundred times in a row with it; how to wire it is in CLAUDE.md.
