# ADR-0016: Each editor integration is a repository of its own in ide4cj

Status: accepted, 2026-09-27

## Context

The Neovim integration lived in `editors/nvim`, rust-analyzer's `editors/code` layout. Plugin managers (`vim.pack`, lazy.nvim) clone a whole repository and put its root on the `runtimepath`: a subdirectory needed a shim at this repository's root sourcing `editors/nvim/plugin/` by hand (#29), and every user would clone the server's sources to get a few Lua files. Zed's extension registry likewise takes an extension as a repository. cjls moved to the `ide4cj` organization, whose aim is the Cangjie developer experience as a whole, not this server alone.

## Decision

- Neovim: [`ide4cj/cangjie.nvim`](https://github.com/ide4cj/cangjie.nvim), a Cangjie plugin rather than a cjls one — the server's `lsp/cjls.lua` (nvim-lspconfig's format), its download from this repository's releases (D11), the ftplugin, and highlighting from [tree-sitter-cangjie](https://github.com/BonZirka/tree-sitter-cangjie) until the server answers semantic tokens.
- The plugin pins the cjls release it downloads, the one it was tested with; a new release is a change to the plugin.
- This repository's CI runs the plugin's smoke test against the binary it has just built, so a server change that breaks the plugin fails here. The plugin's own CI runs it against the latest release.
- VS Code and Zed, when they come, are repositories of their own the same way.

## Consequences

- No `editors/` here; nothing here is loaded by an editor but the binary.
- A change the plugin needs from the server (a new extension, D15) is two pull requests, the server's first.
- The plugin's smoke test is the contract between the two: its `test/smoke.lua` takes the binary from `CJLS_BIN`.
