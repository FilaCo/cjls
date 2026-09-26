# ADR-0012: Paths are `std.fs.Path`, URIs are stdx's `URL`; Windows drives are spelled one way

Status: accepted, 2026-09-26

## Context

`VfsPath` took only `/`-rooted paths, so a Windows client's `file:///c%3A/src/a.cj` became a virtual path, never read from disk (Q5). Clients disagree on the spelling: VS Code lowercases the drive letter and escapes its colon, Neovim sends `file:///C:/src/a.cj`. The URI was parsed and escaped by hand, and the path normalized by splitting on `/`, though `stdx.encoding.url` and `std.fs.Path` do both.

## Decision

- A path on disk is a `std.fs.Path`: absolute and normalized as the platform the server runs on says (`/…` on POSIX, `c:\…` on Windows). `VfsPath.filePath` is a `?Path`.
- A URI goes through `stdx.encoding.url.URL`: `URL.parse` unescapes, drops `/./` and `..`, and refuses a malformed escape (the URI then stays virtual); `URL(scheme: "file", …).toString()` escapes.
- What neither knows is ours, and only on Windows: in a URI the drive is the first segment (`/c:/src`, RFC 8089), and a drive path is kept with `\` and a lowercase letter, so VS Code's and Neovim's spellings give one `VfsPath`. It goes back out as `file:///c:/src/a.cj`, which both read as they read `c%3A`.

## Consequences

- Tests of drive paths run on Windows only (`VfsPathOnWindowsTest`), those of `/` paths on POSIX only; CI runs both. A test needing just some absolute path takes one under `getTempDirectory()`.
- Two paths differing only in the case of a later segment stay two files, as on a case-sensitive file system; Windows would call them one. Folding case would need the name the disk has, which the server does not ask for yet.
- `stdx.encoding.url` adds ~200 KB to the binary.
