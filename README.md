# cjls

A language server for [Cangjie](https://cangjie-lang.cn), written in Cangjie, after
[rust-analyzer](https://rust-analyzer.github.io): incremental, answering from a snapshot while you type,
reporting no error in code the compiler accepts.

It is early: each file is read on its own, from its syntax. What it does today is in the
[changelog](CHANGELOG.md) — document symbols, syntax errors, semantic highlighting; names, types,
completion and go-to-definition are to come.

## Install

**Neovim** 0.11 or newer: [cangjie.nvim](https://github.com/ide4cj/cangjie.nvim) downloads the server
and starts it on `.cj` files.

**Any other editor**: download the archive for your platform from the
[latest release](https://github.com/ide4cj/cjls/releases/latest) — macOS arm64, Linux x64, Windows
x64 — check it against `SHA256SUMS`, and put `cjls` on your `PATH`. The binary is static and needs no
Cangjie SDK. Run it over stdio, with the nearest `cjpm.toml`'s directory as the root. `CJLS_LOG_LEVEL`
(`OFF`, `ERROR`, `WARN`, `INFO` by default, `DEBUG`, `TRACE`) sets what it logs to stderr.

VS Code and Zed extensions are planned.

## Build

The toolchain is the Cangjie nightly named in [`.cangjie-version`](.cangjie-version), with its stdx:

```sh
python3 .github/actions/setup-cangjie/setup.py "$(cat .cangjie-version)" ~/.cangjie-nightly
# then the exports it prints, and
cjpm build          # target/release/bin/cjls
cjpm test
```

How the code is laid out and why is in [`docs/`](docs/README.md); building, testing and commits in
[CLAUDE.md](CLAUDE.md); adding a request in [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Licensed under either of [Apache License, Version 2.0](LICENSE-APACHE) or [MIT license](LICENSE-MIT)
at your option. Unless you explicitly state otherwise, any contribution intentionally submitted for
inclusion in cjls by you, as defined in the Apache-2.0 license, shall be dual licensed as above,
without any additional terms or conditions.

`modules/cjtoml` is a vendored copy of Huawei's TOML library, under Apache-2.0 with Runtime Library
Exception, as its files state; it is used by the code generators only, not by the server.
