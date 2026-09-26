# Neovim

Neovim 0.11 or newer. Put this directory on the `runtimepath` and enable the server:

```lua
vim.opt.runtimepath:append('/path/to/cjls/editors/nvim')
vim.lsp.enable('cjls')
```

| File | What it does |
|---|---|
| `lsp/cjls.lua` | the server's `vim.lsp.Config`, in nvim-lspconfig's format: `cjls` from `PATH`, rooted at the nearest `cjpm.toml` |
| `ftplugin/cangjie.lua` | `//` comments (`gc`), 4-space indentation as cjfmt writes it |
| `plugin/cangjie.lua` | `*.cj.macrocall` as Cangjie; the tree-sitter grammar for nvim-treesitter (D16) |

Neovim detects `*.cj` itself.

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
