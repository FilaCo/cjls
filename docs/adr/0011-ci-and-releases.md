# ADR-0011: A pinned nightly toolchain, CI on three platforms, releases from `cog bump`

Status: accepted, 2026-09-26

## Context

Nothing checked the server off a developer's machine: `cjpm test` ran in the `pre-push` hook, the Neovim smoke test by hand, and there was no binary for an editor to download. The code tracks the 1.3.0 nightlies (the stable SDK is behind them), and their stdx ships separately. `cangjie_test`'s LSP suite (`HLT/Tools/cjlsp`) expects the official `LSPServer`'s output to the letter, so it cannot judge another server.

## Decision

- The toolchain is one nightly tag of [Cangjie/nightly_build](https://gitcode.com/Cangjie/nightly_build/releases), in `.cangjie-version`, bumped on purpose. `.github/actions/setup-cangjie` installs that SDK and its stdx and loads the environment `envsetup` would; the same `setup.py` installs it locally.
- stdx is unpacked as its zips lay it out, `${CANGJIE_HOME}/third_party/stdx/<os>_<arch>_cjnative`, and the root `cjpm.toml` names the static one for each target: `darwin_aarch64`, `linux_x86_64`, `windows_x86_64`.
- CI (`.github/workflows/ci.yml`) on macOS arm64, Linux x64 and Windows x64: `cjpm build`, `cjpm test`, then the binary alone, without the SDK, through the end-to-end tests and the Neovim smoke test. A PR's commits and its title (the squash commit) are checked by `cog`.
- End-to-end tests are [pytest-lsp](https://lsp-devtools.readthedocs.io/) in `tests/e2e`: the binary over stdio, with the capabilities real editors send. `cangjie_test` is a source of scenarios, not a suite to pass.
- `cog bump --auto` on master sets the version (`modules/cjls/cjpm.toml`, `VERSION` in `handlers/lifecycle.cj`), tags `vX.Y.Z` and pushes; `release.yml` runs CI on the tag and attaches the binaries it built and tested, with the changelog.

## Consequences

- A red build names the code, not the toolchain: a nightly moves only when `.cangjie-version` does.
- Windows is a supported platform from now on: stdio, paths (D12) and the build have to hold there.
- A PR title that is not a conventional commit fails CI, since it becomes the commit `cog bump` reads.
