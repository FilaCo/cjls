# Changelog
All notable changes to this project will be documented in this file. See [conventional commits](https://www.conventionalcommits.org/) for commit guidelines.

- - -

## v0.1.0

The first release of cjls, a language server for [Cangjie](https://cangjie-lang.cn) written in Cangjie. It reads each file on its own, from its syntax: no names are resolved and no types inferred yet, so everything below holds for code that does not compile as well.

#### What it does

- **Document symbols** (`textDocument/documentSymbol`): the outline of a file — classes, structs, interfaces, enums and their constructors, extensions, functions and methods, `main`, macros, constructors, properties, fields, variables, type aliases — nested as declared.
- **Syntax errors** as diagnostics: pulled (`textDocument/diagnostic`) by a client that can, pushed (`textDocument/publishDiagnostics`) after every change to one that cannot. The parser follows the compiler's own: checked against its test suite (~98k files), it reports no error in a file the compiler parses.
- **Semantic highlighting** (`textDocument/semanticTokens/full` and `/range`): keywords, including contextual ones where they are keywords; comments, documentation apart; literals and the code inside interpolated strings; operators; builtin annotations and macro calls; names where they are declared, by kind, with `declaration`, `readonly`, `static` and `deprecated`; type names and builtin types.
- **Document sync**: incremental changes, positions in UTF-8 when the client offers it and UTF-16 otherwise.
- **Responsive while typing**: every request is answered from a snapshot of the files as it arrived; one the files changed under is cancelled (`ContentModified`), and results are computed incrementally, only what an edit touched computed again.

#### Where it runs

- One static binary for macOS arm64, Linux x64 and Windows x64, each tested end to end with the capabilities VS Code and Neovim send. It needs no Cangjie SDK.
- **Neovim** 0.11 or newer: [cangjie.nvim](https://github.com/ide4cj/cangjie.nvim) downloads this release and starts it on `.cj` files. Any other editor that speaks LSP over stdio can run `cjls` itself, with the nearest `cjpm.toml` as the root.

- - -
