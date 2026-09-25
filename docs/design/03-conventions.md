# Conventions

| # | Rule |
|---|---|
| C1 | No empty `public init() {}`: a type with no constructor has an implicit parameterless one, visible as the type is, across modules too. Write `init()` only beside other constructors. |
| C2 | A field set from a constructor parameter as is is declared in the primary constructor (`Parser(let input: Input<K>, let eof: K) {}`); other fields stay in the body. |
| C3 | A primary constructor lists regular parameters before field ones (the compiler refuses the other order); when that would reorder a public API, keep `init` (`GreenNode(kind, children)`). |
| C4 | Other constructors delegate to the primary one: `public init(text: String) { this(rooted(chunked(text), 0)) }`. |
