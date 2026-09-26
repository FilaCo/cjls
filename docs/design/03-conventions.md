# Conventions

| # | Rule |
|---|---|
| C1 | No empty `public init() {}`: a type with no constructor has an implicit parameterless one, visible as the type is, across modules too. |
| C2 | One constructor → it is the primary one. Several → one is primary, the rest delegate to it with `this(...)` (`Rope(root)`, `init(text) { this(rooted(chunked(text), 0)) }`). Exception: only where that hurts readability or performance, with a comment why. |
| C3 | A field set from a parameter as is is declared in the primary constructor (`Parser(let input: Input<K>, let eof: K) {}`); other fields stay in the body, set there or by their initializers. |
| C4 | Regular parameters come before field ones (the compiler refuses the other order); reorder the API for it: `GreenNode(children, kind)`. |
| C5 | No foreign call blocks for long: while a thread is in one, the runtime cannot finish a garbage collection — the collector spins at full CPU, and every other thread stops at its next allocation. Wait in slices that return to Cangjie between them (`poll` with a timeout, as `StdinStream` does in `cjls/src/stdio.cj`), and call C only once it will not block. The same holds for an array pinned by `acquireArrayRawData`. |
