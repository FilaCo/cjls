# ADR-0001: Files are persistent ropes; lines break at `\n`

Status: accepted, 2026-09-24

## Context

- An input's old value and every snapshot keep a file's text alive while it is edited.
- LSP positions are line/column in UTF-8, UTF-16 or UTF-32.
- The compiler's lexer takes `\n` and `\r\n` as line ends, not a lone `\r`.

## Decision

- `Rope`: immutable B-tree of UTF-8 chunks; an edit rebuilds the path it touches.
- Each node caches bytes, UTF-16 units, chars, `\n`s: any conversion goes straight down.
- Lines break at `\n` only; `lineEnd` stops before the `\r` of `\r\n`.

## Consequences

- An edit is O(log n); an old version costs nothing to keep.
- A column past the end of a Windows line never splits `\r\n`.
- Lone `\r` is not a line end, unlike the LSP spec, like the compiler.
