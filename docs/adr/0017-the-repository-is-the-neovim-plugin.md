# ADR-0017: The repository is the Neovim plugin, and the plugin downloads the server from its release

Status: accepted, 2026-09-26

## Context

Neovim users install plugins with a plugin manager — `vim.pack` (Neovim 0.12, kickstart.nvim's), lazy.nvim — which clones a repository and puts its root on the `runtimepath`. The Neovim integration is `editors/nvim` (D16), a subdirectory: neither manager takes one, and a directory added to the `runtimepath` after startup gets its `lsp/` and `ftplugin/` read on demand but its `plugin/` never sourced (measured with lazy.nvim). A plugin repository of its own (`cjls.nvim`) would need a second repository kept in step by CI.

The server is a binary. Mason, which installs servers for kickstart and LazyVim, knows only what its registry lists, and the registry takes a package once there are releases to point at; nvim-lspconfig likewise. `release.yml` publishes, per release, `cjls-<target>` archives and their `SHA256SUMS` (D11).

## Decision

- The repository root carries one file, `plugin/editors_nvim.lua`, which appends `editors/nvim` to the `runtimepath` and sources its `plugin/` files, guarded against a second sourcing. `vim.pack.add({ 'https://github.com/FilaCo/cjls' })` or `{ 'FilaCo/cjls' }` in lazy.nvim is the whole setup.
- The plugin enables `cjls` itself (`vim.lsp.enable`), as a language plugin does; configuration goes through `vim.lsp.config`. `lsp/cjls.lua` stays in nvim-lspconfig's format, `cmd = { 'cjls' }`.
- When the configured `cmd` is the bare `cjls` and none is on `PATH`, the plugin downloads, at the first Cangjie buffer of a session, the release its checkout is built on (`git describe --tags --abbrev=0`; the latest release without a tag), checks the archive against `SHA256SUMS`, and unpacks it into `stdpath('data')/cjls/bin`, appended to `PATH` so a `cjls` of one's own wins. The installed release is recorded, and a checkout that moved to another release downloads that one. `:CjlsInstall` downloads it again. It needs `curl` and `tar`.

## Consequences

- A plugin manager's update of the plugin updates the server with it, one version for both, with no build step to configure.
- Only the release targets have a download (macOS arm64, Linux x64, Windows x64); elsewhere the user builds `cjls` and puts it on `PATH`.
- Until the first release there is nothing to download: the plugin says so and asks for a `cjls` on `PATH`.
- Mason and nvim-lspconfig remain the next step once releases exist; the plugin then adds only what they do not have (ftplugin, the grammar).
