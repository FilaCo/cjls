# ADR-0012: A drive path is absolute on every platform, spelled as VS Code spells it

Status: accepted, 2026-09-26

## Context

`VfsPath` took only `/`-rooted paths, so a Windows client's `file:///c%3A/src/a.cj` became a virtual path, never read from disk (Q5). Clients disagree on the spelling: VS Code lowercases the drive letter and escapes its colon, Neovim sends `file:///C:/src/a.cj`; paths from the file system use `\`.

## Decision

- A path is absolute from `/` or from a drive (`C:`, alone or before `/` or `\`), whatever the platform the server runs on.
- A drive path is kept with `/` separators and its letter lowercase: `c:/src/a.cj`. The rest keeps its case.
- In a URI the drive is the first segment (`/c:/…`); `toUri` writes it as VS Code does, `file:///c%3A/src/a.cj`.

## Consequences

- One path, one `VfsPath`, whichever client sent it; tests of Windows paths run on every platform.
- Two paths differing only in the case of a later segment stay two files, as on a case-sensitive file system; Windows would call them one. Folding case would need the name the disk has, which the server does not ask for yet.
