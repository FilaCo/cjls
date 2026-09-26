# ADR-0016: A release every week from a green master; the first one by hand; versions of cjls's own

Status: accepted, 2026-09-26

## Context

D11 says how a release is made (`cog bump --auto`, then `release.yml`), not when; none has been made. R1 releases every Monday, its tags dates, with a nightly beside it; R2 releases `0.0.x` as often. zls ties its version to Zig's, because the language it parses breaks with every Zig release. The cjls binary is static and links no SDK (D11), so the toolchain it is built with never reaches a user; what ties it to Cangjie is the language it parses, and later the SDK's `.cjo` (Q11) and macros (Q9), read from the user's own SDK.

A tag pushed by a workflow with `GITHUB_TOKEN` starts no other workflow: `release.yml` would never run.

## Decision

- **Versions are cjls's own**: semver `0.x`, from the conventional commits (`cog`), not Cangjie's. Which SDKs a release works with goes into its notes once it reads anything from one.
- **The first release, `v0.1.0`, is made by hand**: `cog bump --version 0.1.0` on a green master. It runs the hooks, the changelog and `release.yml` for the first time with someone watching, and its number is a choice, not arithmetic.
- **Then a train, every Monday** (`.github/workflows/bump.yml`): `cog bump --auto` on master, unless no `v*` tag exists yet, CI has not passed on master's head, or nothing since the last tag calls for a release (`docs`, `ci`, `chore` only). It pushes with `RELEASE_TOKEN`, a token allowed to push to master, so the tag starts `release.yml`. `workflow_dispatch` releases off the train.

## Consequences

- A fix reaches users within a week, or at once by dispatch.
- A red master skips the week rather than shipping; `release.yml` runs CI once more on the tag.
- The repository needs the `RELEASE_TOKEN` secret; the release commit on master is the bot's.
- No nightly channel yet: one comes with an editor extension that has a pre-release channel to take it.
