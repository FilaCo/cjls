# ADR-0012: A drive path is absolute on every platform; URIs are stdx's `URL`

Status: accepted, 2026-09-26

## Context

`VfsPath` took only `/`-rooted paths, so a Windows client's `file:///c%3A/src/a.cj` became a virtual path, never read from disk (Q5). Clients disagree on the spelling: VS Code lowercases the drive letter and escapes its colon, Neovim sends `file:///C:/src/a.cj`; paths from the file system use `\`. The URI itself was parsed and escaped by hand, though `stdx.encoding.url` does both.

## Decision

- A path is absolute from `/` or from a drive (`C:`, alone or before `/` or `\`), whatever the platform the server runs on.
- A drive path is kept with `/` separators and its letter lowercase: `c:/src/a.cj`. The rest keeps its case.
- URIs go through `stdx.encoding.url.URL`: `URL.parse` unescapes, drops `/./` and `..`, and refuses a malformed escape (the URI then stays virtual); `URL(scheme: "file", …).toString()` escapes. In a URI the drive is the first segment, written `file:///c:/src/a.cj` (RFC 8089; VS Code and Neovim read it as they read `c%3A`).

## Consequences

- One path, one `VfsPath`, whichever client sent it; tests of Windows paths run on every platform.
- Two paths differing only in the case of a later segment stay two files, as on a case-sensitive file system; Windows would call them one. Folding case would need the name the disk has, which the server does not ask for yet.
- `stdx.encoding.url` adds ~200 KB to the binary.
