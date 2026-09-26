# ADR-0016: Speed and memory are measured over stdio, by one driver for every server

Status: accepted, 2026-09-26

## Context

cjls is to be compared with its competitors, R4 LSPServer and R9 lin-qingying/cangjie (D15), in speed and memory, and its own numbers followed from commit to commit. The two are different jobs: a competitor changes with its own releases (R4 with each SDK nightly, R9 is built from source), so comparing with it on every commit measures them, not us; a regression of cjls has to be seen on the commit that made it. `@Bench` (C7) measures a function; what an editor waits for is the process: startup, the first answer on a file, an answer after each keystroke, and what the process holds.

R1 follows its own numbers per commit (`analysis-stats`, the metrics page); R5 keeps benchmarks that take the binary to run as a flag (`-gopls_path`), so one version is compared with another. Neither compares itself with another server.

## Decision

- **One driver, `tests/perf`**, drives a server over stdio as an editor does (pygls, as `tests/e2e`), and knows no server: `servers.toml` says how to start each (command, environment, `initializationOptions`, when it counts as ready, whether it needs a cjpm project). A new server is an entry there, no code.
- **The same driver serves both jobs.** Against the competitors it is run by hand, when one of them or cjls has changed enough, and the result goes to `prior-art.md`. On cjls it runs in CI on every commit.
- **Scenarios measure what the servers share**: a scenario needing a capability a server does not advertise is skipped, never failed. Each starts a process of its own; a start is thrown away first.
- **Memory is the RSS of the process tree**, sampled: R9 is a launcher starting a JVM. What is inside the heap (Cangjie's heap against native, what holds it) is cjls's own business, by `std.runtime` and `cjprof heap` behind a request of ours, not the driver's.
- **The workspace is generated**, the same every time (a cjpm project cjc builds without errors), or a project given with `--workspace`.
- **A report is JSON**: commit, toolchain, host, and every run of every metric; `compare` makes a Markdown table of several.
- **CI keeps the report as an artifact**, without a threshold: timings on shared runners are too noisy to fail a build on. A history with thresholds needs metrics that noise does not move (instructions, allocations), and is decided in #22.

## Consequences

- R9 is measured once it is built (`CANGJIE_KT_LS`); until then it is reported unavailable, not failed.
- R4 needs its readiness defined: it sends no `$/progress`, only a malformed `window/workDoneProgress/create` without an `id`, which the report notes.
- A new feature of cjls brings its scenario once a competitor has it too (diagnostics, semantic tokens).
