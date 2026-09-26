# Neovim

Neovim 0.11 or newer. The repository is itself the plugin: install it with your plugin manager and
open a `.cj` file. The server starts on its own, and the first time it downloads its binary from
the GitHub release the plugin belongs to (see [The server binary](#the-server-binary)).

## Install

`vim.pack` (Neovim 0.12):

```lua
vim.pack.add({ 'https://github.com/FilaCo/cjls' })
```

[lazy.nvim](https://lazy.folke.io):

```lua
{ 'FilaCo/cjls' }
```

[kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim) is on `vim.pack`: put the line above in
`lua/custom/plugins/cjls.lua` and uncomment `require 'custom.plugins'` at the end of `init.lua`.
Don't add `cjls` to its `servers` table: those are the servers Mason installs, and Mason does not
know cjls. For highlighting, run `:TSInstall cangjie` once; kickstart starts it in Cangjie buffers
from then on (it lists the parsers it installs by itself before the plugin loads).

By hand, from a clone:

```lua
vim.opt.runtimepath:append('/path/to/cjls/editors/nvim')
```

Plugin managers install the whole repository; `plugin/editors_nvim.lua` at its root puts this
directory on the `runtimepath`.

| File | What it does |
|---|---|
| `lsp/cjls.lua` | the server's `vim.lsp.Config`, in nvim-lspconfig's format: `cjls` from `PATH`, rooted at the nearest `cjpm.toml` |
| `plugin/cjls.lua` | `vim.lsp.enable('cjls')`, `:CjlsInstall`, the download when there is no `cjls` on `PATH` |
| `lua/cjls/install.lua` | the download itself |
| `ftplugin/cangjie.lua` | `//` comments (`gc`), 4-space indentation as cjfmt writes it |
| `plugin/cangjie.lua` | `*.cj.macrocall` as Cangjie; the tree-sitter grammar for nvim-treesitter (D16) |

Neovim detects `*.cj` itself. Settings go through `vim.lsp.config`, as for any server:

```lua
vim.lsp.config('cjls', { cmd_env = { CJLS_LOG_LEVEL = 'DEBUG' } })
```

## The server binary

A `cjls` on `PATH` always wins. Without one, at the first Cangjie buffer of a session, the plugin
downloads the archive `release.yml` publishes for this platform — macOS arm64, Linux x64, Windows
x64 — checks it against the release's `SHA256SUMS`, and unpacks it into
`stdpath('data')/cjls/bin` (`~/.local/share/nvim/cjls/bin`), which it appends to `PATH`. It needs
`curl` and `tar`, as Windows 10 and later ship them.

The release is the one the plugin's checkout is built on: its tag, or the last tag before it (the
latest release when there is none). So when the plugin manager updates the plugin past a new
release, the next session downloads that release too. `:CjlsInstall` downloads it again.

Elsewhere, or to run your own build, put `cjls` on `PATH`, or point the server at it:

```lua
vim.lsp.config('cjls', { cmd = { '/path/to/cjls/target/release/bin/cjls' } })
```

The plugin then downloads nothing.

## Highlighting

Until the server answers semantic tokens, highlighting, folds, indentation and text objects come
from [tree-sitter-cangjie](https://github.com/BonZirka/tree-sitter-cangjie), at the revision
pinned in `plugin/cangjie.lua`. With [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
on its `main` branch (it needs the `tree-sitter` CLI and a C compiler):

```vim
:TSInstall cangjie
```

The download is large — the grammar's repository carries its test corpus. nvim-treesitter does
not start highlighting by itself; if your config does not already, do it for Cangjie buffers:

```lua
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'cangjie',
  callback = function(args)
    vim.treesitter.start(args.buf, 'cangjie')
    vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
    vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
  end,
})
```

Without the grammar Neovim falls back to its own `syntax/cangjie.vim`.

## Test

```sh
cjpm build && nvim --clean --headless -u editors/nvim/test/smoke.lua
```
