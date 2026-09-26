# ADR-0020: A release every week from a green master; the first one by hand, its changelog written; versions of cjls's own

Status: accepted, 2026-09-27

## Context

D11 says how a release is made (`cog bump --auto`, then `release.yml`), not when; none has been made. R1 releases every Monday, its tags dates, with a nightly beside it; R2 releases `0.0.x` as often. zls ties its version to Zig's, because the language it parses breaks with every Zig release. The cjls binary is static and links no SDK (D11), so the toolchain it is built with never reaches a user; what ties it to Cangjie is the language it parses, and later the SDK's `.cjo` (Q11) and macros (Q9), read from the user's own SDK.

A changelog made from the whole history is ~40 commits of builds and refactors, one of them (`2b76e64`, #5) not a conventional commit; it says nothing of what the server does. Rewriting that commit would change every commit after it on master.

`cog bump` commits the version to master, and the `Protect master` ruleset lets only admins push there without a PR; `GITHUB_TOKEN` is not one. A tag pushed with `GITHUB_TOKEN` starts no other workflow either, so `release.yml` would not run.

## Decision

- **Versions are cjls's own**: semver `0.x`, from the conventional commits (`cog`), not Cangjie's. Which SDKs a release works with goes into its notes once it reads anything from one.
- **The first release, `v0.1.0`, is made by hand**: its section of `CHANGELOG.md` is written, not generated — what the server does, where it runs, how an editor gets it — and a maintainer pushes the tag `v0.1.0` on a green master; the version is `0.1.0` in the sources already. `2b76e64` stays as it is: `cog` reads from the latest tag, so after `v0.1.0` it is never read again.
- **Then a train, every Monday** (`.github/workflows/bump.yml`): `cog bump --auto` on master, unless no `v*` tag exists yet, CI has not passed on master's head, or nothing since the last tag calls for a release (`docs`, `ci`, `chore` only). `cog` inserts each section above the ones before, written ones included. It pushes with `RELEASE_TOKEN`, an admin's fine-grained token (contents: write on this repository), so the commit gets past the ruleset and the tag starts `release.yml`. `workflow_dispatch` releases off the train.
- **The notes of a release are its section of `CHANGELOG.md`**, written or generated alike, so the file and the GitHub release never differ.
- **cjls is `MIT OR Apache-2.0`**, as R1 is. The vendored `cjtoml` keeps its own license (Apache-2.0 with Runtime Library Exception) and is not in the binary.

## Consequences

- A fix reaches users within a week, or at once by dispatch.
- A red master skips the week rather than shipping; `release.yml` runs CI once more on the tag.
- The repository needs the `RELEASE_TOKEN` secret, and the train stops when it expires; the release commit on master is the bot's. A GitHub App in the ruleset's bypass list would take its place without a person's token.
- No nightly channel yet: one comes with an editor extension that has a pre-release channel to take it.
