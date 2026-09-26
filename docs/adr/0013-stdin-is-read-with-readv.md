# ADR-0013: Stdin is read with `readv`, not `read`

Status: accepted, 2026-09-26

## Context

An idle `cjls` burnt a full core and stopped answering: the garbage collector spun in `MutatorManager::EnsurePhaseTransition` waiting for the thread blocked in `read(2)` on stdin, and every other thread stopped at its next allocation, until the client next wrote. A foreign call normally goes through `_CJ_MCC_C2NStub`, which marks the thread as in native code, so a collection does not wait for it. cjc (1.3.0-alpha, nightlies 20260918 and 20260925, `-O0` and `-O2` alike) leaves the stub out for a `foreign func` named like a C library function LLVM knows (`TargetLibraryInfo`: `read`, `pread`, `write`, `open`, `getchar`, `fgets`, `malloc`, …): the call is compiled as if marked `@FastNative`, which must not block. `readv`, `recv`, `poll`, `select`, `usleep`, `close` and `_read` are not such names and get the stub; a `@FastNative readv` stalls exactly as `read` does. Nothing turns the implicit `@FastNative` off.

The first fix waited in 50 ms `poll` slices and read only once input was there: it works, but because `poll` gets the stub, not because the waits are short.

## Decision

- On POSIX, `StdinStream` reads with `readv` of one buffer: `read(2)`'s semantics, under a name cjc does not treat as fast. It blocks in C for as long as the client is idle; no `poll`, no slices.
- On Windows it calls `_read` directly: not a known name either. No `PeekNamedPipe`, no `sleep`.
- The buffer is the Cangjie array pinned by `acquireArrayRawData`: measured, a pin held across the blocking call does not hold up a collection.

## Consequences

- An idle server makes no system calls and wakes up for nothing.
- The workaround rests on a compiler detail: if cjc ever gives `readv` the same treatment, the idle server stalls again. `tests/e2e/test_idle.py` fails then (it times out with `read`), on every platform CI runs.
- Any foreign function that can block has to be checked by name, not only stdin's (C5).
