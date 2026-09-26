# ADR-0016: Editors highlight with tree-sitter-cangjie until the server has semantic tokens

Status: accepted, 2026-09-26

## Context

cjls answers no `textDocument/semanticTokens` yet (#16), and Neovim ships only a regex `syntax/cangjie.vim` and no ftplugin: no comment string, 8-column tabs. Neovim, Zed and Helix highlight, fold, indent and select with tree-sitter, and need a grammar for it whatever the server does. [BonZirka/tree-sitter-cangjie](https://github.com/BonZirka/tree-sitter-cangjie) (MIT) commits its generated `parser.c` and external scanner, and has highlights, folds, indents, locals and text objects queries — nvim-treesitter's `main` branch builds it without `tree-sitter generate`.

Writing a tree-sitter grammar of our own would be a second Cangjie parser beside `cjsyntax` to keep in step with cjc (D10, D15), for highlighting only.

## Decision

- The editor integrations take their grammar from tree-sitter-cangjie, pinned to a commit: `editors/nvim/plugin/cangjie.lua` registers it with nvim-treesitter (on `User TSUpdate`), queries included. Its queries are used as they are; where a capture name is not Neovim's (`@parameter`), a default link maps it (`@variable.parameter`).
- The pin moves by hand, after checking the queries still load against the parser and the smoke test passes.
- `editors/nvim` also carries the ftplugin Neovim lacks (`//` comments, 4-space indentation as cjfmt writes) and detects `*.cj.macrocall`.

## Consequences

- Highlighting works before the server knows any types; semantic tokens, once there (#16), refine it rather than replace it, as rust-analyzer's do over a tree-sitter grammar.
- The grammar is a third parser whose disagreements with cjc and `cjsyntax` a user sees as wrong colours, not wrong diagnostics; the server stays the authority.
- `:TSInstall cangjie` downloads the grammar's whole repository, test corpus included (~80 MB at the pinned commit).
- Zed and VS Code will need the same grammar wired their own way (a Zed extension names it by repository and commit; VS Code highlights with TextMate, not tree-sitter).
