# `lsp_codegen` — design

Turns `modules/cjls/metaModel.json` (LSP 3.18.0) into idiomatic Cangjie declarations plus
their `DataModel` serialization, so the LSP layer above `jsonrpc` is typed rather than
hand-written.

Its two hard requirements: **output location is configuration**, and **the emitted code
reads like Cangjie a person would write**, deviating from LSP shape only where Cangjie
leaves no faithful option.

## What the input actually contains

Numbers matter here — they decide which cases deserve machinery and which deserve a
special case. From the checked-in `metaModel.json` (v3.18.0):

| | count | notes |
|---|---|---|
| `structures` | 387 | 66 use `extends`, 87 use `mixins`; max 2 of each, no `and` types |
| `enumerations` | 40 | 15 string-valued, 25 numeric; **9** are `supportsCustomValues` |
| `typeAliases` | 23 | 15 of them are unions |
| `requests` | 69 | 29 with `partialResult`, 3 with `errorData`, 53 with `registrationOptions` |
| `notifications` | 26 | every message has a `typeName` |
| `or` types | 137 | **44** are `T \| null`; the rest reduce to **73 distinct** real unions |
| `map` | 6 | all `string`/`DocumentUri` keyed |
| `tuple` | 1 | `ParameterInformation.label: string \| [uinteger, uinteger]` |
| `literal` (anon object) | 2 | both `{}` (`SemanticTokensOptions.range`, `ClientSemanticTokensRequestOptions.range`) |
| `stringLiteral` properties | 9 | all named `kind` — these are union discriminators |
| property axes | | 327 required, 477 optional, 6 nullable, 4 optional+nullable |

Two structural facts shape the whole design: the union surface is small enough (73) to
name and emit individually, and the discriminator story is already in the model (`kind`).

### Cangjie facts verified against `cjc` 1.1.3

Each of these was compiled, not assumed.

- **The keyword collision surface is tiny.** All 596 distinct identifiers the metaModel would
  produce (every property name and every enumeration value name) were compiled as both a field
  name and an enum constructor. Exactly **10** are rejected: `class`, `enum`, `import`,
  `interface`, `macro`, `operator`, `static`, `struct`, `type`, `Unit`. Nine of those ten are
  lowercase enum *value* names that the generator title-cases anyway — see *Identifiers*.
- **Primitive type keywords cannot be enum constructors.** `enum E { | Int32(Int32) }` fails
  with *"expected a enum value name … found keyword 'Int32'"*. `String`, `Array` and `Object`
  are library types rather than keywords and *do* work unescaped — `stdxx` already ships
  `| String(String)` (`integer_or_string.cj`) and `| Array(DataModelSeq)` (`array_or_object.cj`).
- `from` is **not** a keyword; `CallHierarchyIncomingCall.from` needs no special handling.
- Recursive `struct` compiles both through `Array<T>` and directly through `?T`
  (`struct S { let parent!: ?S }` builds). So `SelectionRange`, `DocumentSymbol` and friends
  need no class/box workaround — **everything can be a `struct`**.
- Recursive `enum` compiles (needed for `LSPAny`).
- `stdx.encoding.url.URL` is a **class implementing `ToString` only** — not `Hashable`, not
  `Equatable`, so it cannot be a `HashMap` key as-is. `URL.parse` throws `UrlSyntaxException`,
  preserves percent-encoding verbatim on `toString()`, decodes `path` for you, and normalizes
  dot segments (`file:///a/dir/../b.cj` → `file:///a/b.cj`). See *URIs*.

## Output contract

The generator owns a directory and nothing else in it.

```
lsp_codegen --src-dir modules/lsp/src --package lsp.types modules/cjls/metaModel.json
```

The metaModel is the positional argument — it is the subject of the command, not a setting.

- `--src-dir` is the target **module's source root**, `--package` the package to emit.
  The output directory is *derived*, not configured: Cangjie's package name mirrors its
  directory, so `modules/lsp/src` + `lsp.types` → `modules/lsp/src/types` (the root package
  component names the src dir itself; each further component is one subdirectory down).
  Two independent flags could disagree — a `package lsp.types` clause emitted into a
  directory named anything else is a package that will not compile — and deriving one from
  the other makes that unrepresentable.
- Validation before any file is written: read `<src-dir>/../cjpm.toml` and fail if
  `[package] name` doesn't match the first component of `--package`. Cheap, and it catches
  the one misconfiguration whose symptom would otherwise be a confusing compiler error in a
  450-file tree.
- Together these satisfy requirement 1: the same binary can target a standalone `lsp`
  module, a subpackage of `cjls`, or a scratch dir for diffing, without recompiling.
- **One file per named type**, `snake_case.cj` (`initialize_params.cj`,
  `string_or_markup_content.cj`) matching the repo's existing file naming. Cangjie compiles
  a package as a unit, so file count costs nothing at build time and buys readable diffs on
  regeneration. Messages go in one `messages.cj`, base aliases in `aliases.cj`.
- Every file opens with `// Code generated by lsp_codegen from metaModel.json 3.18.0. DO NOT EDIT.`
- A `.lsp_codegen_manifest` in the output directory lists what the previous run wrote. A new run
  deletes only those files, so hand-written code can share the directory and a type
  disappearing from the metaModel doesn't leave a stale file behind.

**Default home:** a new workspace member `modules/lsp` (`dynamic`), package `lsp`, depending
on `stdxx` plus `stdx.encoding.url`; generated code lands in the `lsp.types` subpackage, hand-written core
(`DocumentUri`, message-spec interfaces, exceptions) sits in `lsp`. Dependency flow stays
one-way: `cjls → lsp → stdxx` alongside `cjls → jsonrpc → stdxx`. `lsp` deliberately does
**not** depend on `jsonrpc` — types know nothing about transports.

## Type mapping

Mechanical, no judgment per field.

| metaModel | Cangjie |
|---|---|
| `string` | `String` |
| `DocumentUri` (28 uses), `URI` (9) | `DocumentUri` — hand-written wrapper over `stdx.encoding.url.URL`, see *URIs* |
| `integer` | `Int32` |
| `uinteger` | `UInt32` |
| `decimal` | `Float64` |
| `boolean` | `Bool` |
| `null` | only ever inside an `or` — see below |
| `array<T>` | `Array<T>` |
| `map<K, V>` | `HashMap<K, V>` |
| `tuple<A, B>` | `(A, B)` |
| `reference` | the referenced type's name |
| `literal { … }` | lifted to a named struct `<Owner><Property>` (`SemanticTokensRangeOptions`) |
| `stringLiteral` | not a field — see discriminators |
| `or` containing `null` | `Nullable<T>` over the rest |
| `or` without `null` | a generated enum |

`uinteger → UInt32` is the one place faithfulness beats convenience: `Int64` would be
friendlier for arithmetic, but positions and counts are protocol-range-checked values and a
widening `Int64(pos.line)` never throws, while the narrowing direction throwing on a
negative index is a bug worth surfacing (Cangjie's default overflow strategy is throwing).

### Identifiers — no raw identifiers

Backticks are available and they work, but they are the wrong trade. `` `type` `` costs
nothing at the point of *declaration* and then taxes every consumer forever —
`` ShowMessageParams(`type`: MessageType.Error) ``, `` case `String`(s) => … `` — and the
generated code is meant to read like Cangjie a person would write. The generator therefore
**never emits a backtick**. It normalizes, and where normalization is not enough, renames.

Three rules, applied in order:

1. **Normalize case.** Enumeration value names become `UpperCamelCase` (`import` → `Import`,
   `asIs` → `AsIs`, `file` → `File`); open-enumeration constants become `UPPER_SNAKE_CASE`
   (`class` → `CLASS`). Property names are already `lowerCamelCase` and are left alone.
   Cangjie's uppercase keywords are all primitive type names (`Int32`, `Bool`, `Unit`, …), and
   of the 10 collisions only `Unit` is one of those — so this rule alone clears **9 of 10**,
   as a side effect of a casing convention we wanted anyway.
2. **Spell out primitive union members.** A union constructor is never named after a Cangjie
   primitive type, because those *are* keywords: `string → String`, `integer → Integer`,
   `uinteger → UInteger`, `decimal → Decimal`, `boolean → Boolean`. This is exactly the
   naming `stdxx.IntegerOrString` uses today.
3. **Rename the residue from a table.** What survives rules 1–2 is five declarations, listed
   in the config and checked in:

   | declaration | wire name | Cangjie name |
   |---|---|---|
   | `ShowMessageParams`, `ShowMessageRequestParams`, `LogMessageParams` | `type` | `messageType` |
   | `FileEvent` | `type` | `changeType` |
   | `CompletionItemKind` | `Unit` | `UnitKind` |

   Five hand-chosen names, once, in exchange for backtick-free call sites everywhere — and
   each one reads better than the original (`params.messageType` says what `params.type` meant).

**The guard.** `emit` refuses to write an identifier that `cjc` would reject. The generator
carries the keyword list, and an identifier that collides with no rename entry is a **hard
failure naming the declaration**, not a silent backtick. A metaModel bump that introduces a
new collision stops the generator with an actionable message instead of producing a 450-file
tree that does not compile — and regeneration is a manual, reviewed step, so a human is
already there to add the name.

**Consequence for serde.** The Cangjie name is no longer always the wire name, so `FieldIr`
carries **both** `name` and `wireName`, and the emitted `serialize`/`deserialize` use
`wireName` for the JSON key while the struct uses `name`. Same for enumeration values, whose
wire `value` was already independent of the name. This is a one-line change in the IR that
buys the freedom to name things well.

### URIs

`DocumentUri` and `URI` are the same thing in the metaModel and appear 37 times. The previous
plan aliased them to `String`; `type` aliases in Cangjie are transparent, so that bought no
type safety at all and no parsing. `stdx.encoding.url.URL` does the real work — verified
above, it round-trips every realistic LSP URI byte-exactly (`file:///c%3A/Users/foo/bar.cj`,
`file:///a%20b/%D0%BF%D1%80.cj`, opaque `untitled:Untitled-1`) and hands back a decoded
`path`, which is precisely what a language server needs and does not want to hand-roll.

It cannot be used directly, for two reasons found by probing it: `URL` is not `Hashable` or
`Equatable`, and a server keys documents by URI in a `HashMap` constantly; and `toString()`
normalizes dot segments, whereas LSP requires echoing back the exact URI string the client
sent. So `lsp` hand-writes a thin wrapper — small, and not generated:

```cangjie
public struct DocumentUri <: Serializable<DocumentUri> & Equatable<DocumentUri> & Hashable & ToString {
    public let raw: String   // echoed back verbatim — identity is the client's string
    public let url: URL      // parsed once: scheme, decoded path, host
}
```

Identity, equality and serialization are all `raw`; `url` is the accessor for anyone who needs
the filesystem path or scheme. The generator just emits the name `DocumentUri`.

### The two null axes

Straight from CLAUDE.md; the generator composes `optional` (metaModel flag) and `nullable`
(a `null` member in an `or`) independently:

| shape | Cangjie | on write |
|---|---|---|
| required, non-null | `T` | always |
| optional | `field!: ?T = None` | omitted when `None`, never `null` |
| nullable | `Nullable<T>` | always; `Null` → `null` |
| optional + nullable | `field!: ?Nullable<T> = None` | omit `None`; `Some(Null)` → `null` |

Read side uses the presence-aware `DataModelStruct.getOrNone`, which distinguishes an absent
key (`None`) from a present null (`Some(DataModelNull)`). This is **already available**: it
now lives in `modules/stdxx/src/data_model.cj`, exported via the `DataModelFields` interface
so the extension crosses a package boundary. Importing `stdxx` is enough — no prerequisite work.

### Structures

Structural typing has no Cangjie equivalent, so `extends` and `mixins` are **flattened**:
inherited properties are emitted first (in declaration order, `extends` before `mixins`),
then the type's own; a redeclared property is taken from the most derived type. Origin is
recorded in the doc comment (`/** … Inherited from `WorkDoneProgressParams`. */`) so the
flattening is traceable back to the spec.

```cangjie
/**
 * The parameters of a `textDocument/definition` request.
 * @since 3.17.0
 */
public struct DefinitionParams {
    public DefinitionParams(
        /** Inherited from `TextDocumentPositionParams`. */
        public let textDocument!: TextDocumentIdentifier,
        public let position!: Position,
        /** Inherited from `WorkDoneProgressParams`. */
        public let workDoneToken!: ?ProgressToken = None,
        /** Inherited from `PartialResultParams`. */
        public let partialResultToken!: ?ProgressToken = None
    ) {}
}
```

**All parameters are named**, required ones without a default, optional ones defaulting to
`None`. `ClientCapabilities`-scale types make positional constructors unusable, and named
arguments make the generated call sites order-independent — regenerating against a newer
metaModel that inserts a property doesn't silently reshuffle anyone's arguments.

Generated per struct: the struct, an `extend … <: Serializable<T>`, and `ToString` via
`serialize()`. **No `Equatable`** in v1 — it would have to hold transitively through
`Array`/`HashMap`/every union, and nothing needs it yet.

### Enumerations

Two shapes, chosen by `supportsCustomValues`:

- **closed (31)** → a real Cangjie `enum`, so `match` is exhaustive. Constructor names are
  `UpperCamelCase`d (rule 1); the wire value is carried separately, so `MonikerKind.import`
  becomes `Import` without touching the string on the wire. `deserialize` throws
  `DataModelException` on an unknown value; that is what the spec says a closed set means.
- **open (9)** → the `ErrorCode` newtype idiom already used in `jsonrpc`: a struct wrapping
  `String`/`Int32` with `UPPER_SNAKE_CASE` `public static const` members, unknown values
  surviving round-trip. The constant casing is why `SemanticTokenTypes`' seven keyword-named
  values (`class`, `enum`, `interface`, `macro`, `operator`, `struct`, `type`) need nothing.

```cangjie
public enum CompletionItemKind {
    | Text | Method | Function /* … */ | UnitKind /* renamed: `Unit` is a keyword */
}

public struct PositionEncodingKind <: Serializable<PositionEncodingKind> & Equatable<PositionEncodingKind> {
    public static const UTF8 = PositionEncodingKind("utf-8")
    public static const UTF16 = PositionEncodingKind("utf-16")
    public static const UTF32 = PositionEncodingKind("utf-32")
    public PositionEncodingKind(public let value: String) {}
}
```

### Unions

44 of the 137 `or`s are `T | null` and collapse into `Nullable<T>`. The remaining 73
distinct unions each become a named enum with one constructor per member:

```cangjie
public enum StringOrMarkupContent <: Serializable<StringOrMarkupContent> {
    | String(String)
    | MarkupContent(MarkupContent)
}
```

No backticks: `String` is a library type, not a keyword, and `stdxx` already declares exactly
this shape. `integer` and `boolean` members would be `Integer(Int32)` and `Boolean(Bool)` —
never `Int32(…)`, which the parser rejects (rule 2 above).

**Naming.** Canonical name is structural — member names joined with `Or`, primitives spelled
out, arrays pluralised (`Location | [Location]` → `LocationOrLocations`) — which dedups the 93
occurrences down to 73 types automatically. When a `typeAlias` has exactly that definition,
the **alias name wins** (`Definition`, `TextDocumentContentChangeEvent`, `PrepareRenameResult`…)
and further aliases with the same structure become `public type Declaration = Definition`.
The same config table that holds the rule-3 renames also holds structural-name overrides for
the handful that read badly, without touching the algorithm.

One structural name lands on a type `stdxx` already provides: `integer | string` →
`IntegerOrString`, which is exactly the `ProgressToken` alias (and what `jsonrpc` already uses
for `RequestId`). The generator emits no type for it and references `stdxx.IntegerOrString`
instead — a `reuse` entry in the same table.

**Discrimination on deserialize**, in order — the generator picks a strategy per union at
generation time and records which one in a comment above the emitted `deserialize`:

1. **By JSON kind** — if every member maps to a distinct `DataModel` subtype, match on it.
   This covers most of them (`string | MarkupContent`, `boolean | SaveOptions`, …).
   `integer`/`uinteger` collapse to one kind and are treated as ambiguous.
2. **By `kind` discriminator** — object members that all carry a `stringLiteral` property
   with distinct values (`FullDocumentDiagnosticReport | UnchangedDocumentDiagnosticReport`,
   the `WorkDoneProgress*` family, the file-operation family). Match on that string.
3. **By required-property presence** — object members with disjoint required keys
   (`TextDocumentFilterLanguage | …Scheme | …Pattern`). Generated as an explicit key check.
4. **Try in order** — metaModel order, first successful `deserialize` wins, others' failures
   swallowed. Only reached when 1–3 fail; the emitted comment says so, so ambiguity is
   auditable rather than invisible.

`stringLiteral` properties are **not** emitted as fields. They become
`public static const KIND = "full"`, written unconditionally on serialize and verified on
deserialize (throwing on mismatch). A discriminator that cannot be set to the wrong value
cannot desync from its variant.

`LSPAny`/`LSPObject`/`LSPArray` are generated normally — the recursive enum compiles — with
`LSPObject = HashMap<String, LSPAny>`.

### Messages

Per request/notification, keyed on `typeName` (`ImplementationRequest`, `DidOpenTextDocumentNotification`):

```cangjie
public struct ImplementationRequest <: LspRequestSpec<ImplementationParams, Nullable<DefinitionOrDefinitionLinks>> {
    public static const METHOD = "textDocument/implementation"
    public static const DIRECTION = MessageDirection.CLIENT_TO_SERVER
    public static const REGISTRATION_METHOD = "textDocument/implementation"
}
```

`LspRequestSpec<P, R>` / `LspNotificationSpec<P>` are **hand-written** in `lsp`, not
generated — they are the seam the `cjls.macros` handler registration binds against, and
CLAUDE.md already notes those interfaces need reintroducing. The generator emits data only:
method string, direction, params/result/partialResult/errorData/registrationOptions types.
Routing stays entirely in `cjls`; `lsp` learns method names, `jsonrpc` still learns none.

## Generator internals

Four phases, one package (`lsp_codegen`, flat file layout — it is an executable, not a
library):

```
main.cj          std.argopt CLI → Config
config.cj        Config: metaModelPath, srcDir, packageName, the renames/overrides/reuse
                 table; derives the output dir from srcDir + package, validates against the
                 module's cjpm.toml
meta_model.cj    metaModel schema as Cangjie types, parsed via stdx.serialization DataModel
resolve.cj       metaModel → IR: flatten extends/mixins, lift literals, collect + name unions,
                 resolve aliases, pick a discrimination strategy per union
ir.cj            TypeIr / StructIr / EnumIr / UnionIr / FieldIr / MessageIr — every named
                 thing carries both its Cangjie name and its wire name
naming.cj        case normalization, the rename table, the keyword guard (hard-fails on an
                 unlisted collision), snake_case filenames, union naming
writer.cj        indent-aware SourceWriter (emitted text only, no std.ast)
emit_*.cj        emit_struct / emit_enum / emit_union / emit_message / emit_serde / emit_docs
manifest.cj      write outputs, prune stale ones
```

Phase separation is the point: `resolve` makes every decision (names, nullability,
discriminators, ordering) and `emit_*` does no thinking. That keeps naming and mapping rules
unit-testable without touching text output, and makes the emitters small enough to review.

Text emission, not `std.ast` — the target is files on disk, and `quote(…)` buys nothing when
there is no macro expansion context.

`documentation` becomes a `/** … */` doc comment with `*/` escaped, `since` becomes
`@since`, `deprecated` becomes `@deprecated` (1 structure, plus properties).

**Determinism** is a hard requirement: metaModel order is preserved everywhere, maps are
iterated sorted, so regenerating produces a byte-identical tree and a real diff means a real
change.

## Testing

Matching the repo's conventions (`*_test.cj` beside the code, arrange/act/assert, sentence-named cases):

- **Unit** — `naming.cj` and `resolve.cj` are pure functions over small inputs: case
  normalization, the rename table, the keyword guard *failing* on an unlisted collision,
  union naming and dedup, extends/mixins flattening with a redeclared property, the four
  optional/nullable combinations, discrimination-strategy selection per union shape.
- **No backticks** — a whole-tree assertion that no emitted file contains a backtick. One
  line, and it is the thing this design is most likely to regress on.
- **Golden** — a trimmed fixture metaModel in `testdata/` (one struct with inheritance, one
  open and one closed enum, one union per discrimination strategy, one message) generated
  into a temp dir and compared against checked-in expected `.cj` text. Golden files are the
  review surface for "does this read like Cangjie".
- **Compiles** — generating the full 450-type tree and building `modules/lsp` is the only
  proof the emitter is correct; run it in CI, not in `cjpm test`.
- **Round-trip** — in `lsp`, a corpus of real LSP payloads (an `initialize` request, a
  `textDocument/publishDiagnostics`, a completion list) deserialized → serialized →
  compared as `DataModel`. This is where union discrimination and the optional-vs-null
  distinction actually get exercised.

## Generated code is checked in

`modules/lsp/src/types` is committed, regenerated by hand when the metaModel is bumped.
It keeps the build free of a bootstrap dependency (`lsp_codegen` is itself built by `cjpm`),
makes the emitter's output reviewable in PRs, and means a metaModel bump shows up as a diff
rather than as a silent behaviour change. A `pre-build` script (like `build.cj` does for
`stdx`) stays available if regeneration ever becomes routine.

## Build order

1. ~~`stdxx`: promote `getOrNone` to public~~ — **done**, `modules/stdxx/src/data_model.cj`.
2. `modules/lsp` skeleton + hand-written core: `DocumentUri` (the `URL` wrapper, with
   round-trip tests over real client URIs), `LspRequestSpec`, `LspNotificationSpec`,
   exceptions. `modules/lsp` gains a `stdx.encoding.url` dependency.
3. `lsp_codegen`: metaModel parse → IR → emit **aliases and enumerations** end to end.
   Smallest slice that proves the pipeline, config surface and manifest.
4. Structures + `Serializable` emission (the bulk: 387 types).
5. Unions + discrimination strategies.
6. Messages.
7. Reintroduce `@LspRequest`/`@LspHandlers` in `cjls` against the generated specs.

Steps 3–6 each end with the full tree compiling, so the emitter is never more than one
category ahead of proof that it works.
