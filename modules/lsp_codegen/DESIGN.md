# `lsp_codegen` — design

Turns `modules/lsp_codegen/metaModel.json` (LSP 3.18.0) into idiomatic Cangjie declarations plus
their `DataModel` serialization, so the LSP layer above `jsonrpc` is typed rather than
hand-written.

Its three hard requirements: **output location is configuration**; **the output is a complete
subpackage**, not fragments a person has to complete by hand; and **the emitted code reads
like Cangjie a person would write**, deviating from LSP shape only where Cangjie leaves no
faithful option.

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

Each of these was compiled, not assumed. The toolchain has since moved to
**1.3.0-alpha.20260804010019**, on which the full workspace suite passes (243 tests). The
language-level facts below have not been individually re-run; the two that were re-measured on
1.3.0 are recorded under *Emission* (`stdx.syntax`) and immediately below (`funcTable`).

> **The `funcTable` abort no longer reproduces on 1.3.0.** The static-linking rule in
> CLAUDE.md exists because `Array<T>` `Serializable` dispatch at a user-defined `T` aborted
> across a shared-library boundary. On 1.3.0 both documented trigger shapes —
> `Array<T>.deserialize(dm)` at a concrete type and the same call inside a generic
> `func f<T>() where T <: Serializable<T>` — return correct results with the intermediate
> library built `dynamic`, and again with the **dynamic** stdx. Previously only static×static
> survived.
>
> This is a *minimal* reproduction, not the original measurement. Before relaxing any
> `output-type = "static"`, flip them in the real workspace and run `cjpm test` — the bug was
> linkage-sensitive, so a two-module repro passing is suggestive, not conclusive. If it holds,
> CLAUDE.md's static-linking section needs rewriting, not just this file.

- **The keyword collision surface is tiny.** All 596 distinct identifiers the metaModel would
  produce (every property name and every enumeration value name) were compiled as both a field
  name and an enum constructor. Exactly **10** are rejected *unescaped*: `class`, `enum`,
  `import`, `interface`, `macro`, `operator`, `static`, `struct`, `type`, `Unit`. Nine of
  those ten are lowercase enum *value* names that the generator title-cases anyway — see
  *Identifiers*.
- **Raw identifiers work everywhere the generator needs them.** Backticks escape a keyword as
  a struct field (including in named-argument construction and member access), as an enum
  constructor *with a payload*, and in a `match` pattern. In particular
  `` enum E { | `Int32`(Int32) } `` compiles — unescaped `Int32` does not, failing with
  *"expected a enum value name … found keyword 'Int32'"*, which is a lexing rule, not a
  restriction on constructor payload types. Verified by compiling and running all four
  positions.
- `String`, `Array` and `Object` are library types rather than keywords and work unescaped —
  `stdxx` already ships `| String(String)` (`integer_or_string.cj`) and
  `| Array(DataModelSeq)` (`array_or_object.cj`).
- `from` is **not** a keyword; `CallHierarchyIncomingCall.from` needs no special handling.
- **`quote(…)` works outside a macro package**, in a plain executable, and `Tokens.toString()`
  renders indented multi-line source. But the lexer **drops comments** inside `quote`, and
  `toString()` imposes its own layout (`!:?T`, collapsed bodies). `TokenKind.COMMENT` exists
  and prints if constructed explicitly. See *Emission*.
- **An interface cannot declare `static const`** — *"unexpected variable declaration in
  interface body"*. It **can** declare `static prop` and `static func`, and a `static prop` is
  reachable both directly (`T.method`) and through a type parameter (`S.method` under
  `where S <: I<…>`) with no instance. This is what the message specs are built on — see
  *Messages*.
- Recursive `struct` compiles both through `Array<T>` and directly through `?T`
  (`struct S { let parent!: ?S }` builds). So `SelectionRange`, `DocumentSymbol` and friends
  need no class/box workaround — **everything can be a `struct`**.
- Recursive `enum` compiles (needed for `LSPAny`).
- **Module dependencies are not transitive.** A module that imports `stdxx` must declare it in
  its own `cjpm.toml`, even if it already depends on something that depends on `stdxx`; cjpm
  fails the build with *"root package 'app' imports package 'base', but it is not added as a
  dependency in cjpm.toml"*. It attributes the error to the **root** package even when the
  import is in a subpackage — deps are per module, not per package.
- **`public import` re-exports across a module boundary**, in both named
  (`public import base.IntegerOrString`) and wildcard forms, and it carries `extend`-supplied
  interface members too. Verified but **not used** — see *Foreign types in the generated API*.
- `stdx.encoding.url.URL` is a **class implementing `ToString` only** — not `Hashable`, not
  `Equatable`. `URL.parse` throws `UrlSyntaxException`, and `toString()` normalizes dot
  segments (`file:///a/dir/../b.cj` → `file:///a/b.cj`). It is **not used** — see *URIs*.

## Output contract

**The generator emits an entire, self-contained subpackage** — every `.cj` file in the output
directory is generated, including the pieces an earlier draft of this design left
hand-written (base-type aliases, the message-spec interfaces). Nothing in the package is
authored by hand, and it compiles against `stdxx` + `stdx.serialization` and nothing else.
"Self-contained" means no hand-written companion files to complete — not zero dependencies;
generated files import `stdxx` normally (see *Foreign types in the generated API*).

```
lsp_codegen modules/lsp_codegen/metaModel.json --src-dir modules/cjls/src --output-package cjls.lsp_types
```

The metaModel is the positional argument — it is the subject of the command, not a setting.

- `--src-dir` is the target **module's source root**, `--output-package` the package to emit.
  The output directory is *derived*, not configured: Cangjie's package name mirrors its
  directory, so `modules/cjls/src` + `cjls.lsp_types` → `modules/cjls/src/lsp_types` (the root
  package component names the src dir itself; each further component is one subdirectory
  down). Two independent flags could disagree — a `package cjls.lsp_types` clause emitted into
  a directory named anything else is a package that will not compile — and deriving one from
  the other makes that unrepresentable.
- Validation before any file is written: read `<src-dir>/../cjpm.toml` and fail if
  `[package] name` doesn't match the first component of `--output-package`. Cheap, and it
  catches the one misconfiguration whose symptom would otherwise be a confusing compiler error
  in a 450-file tree.
- Together these satisfy requirement 1: the same binary can target a subpackage of `cjls`, a
  future standalone module, or a scratch dir for diffing, without recompiling.
- **One file per named type**, `snake_case.cj` (`initialize_params.cj`,
  `string_or_markup_content.cj`) matching the repo's existing file naming. Cangjie compiles
  a package as a unit, so file count costs nothing at build time and buys readable diffs on
  regeneration. Messages go in one `messages.cj`, base aliases in `aliases.cj`, the spec
  interfaces in `spec.cj`.
- Every file opens with `// Code generated by lsp_codegen from metaModel.json 3.18.0. DO NOT EDIT.`

### Why a subpackage of `cjls`, and why no manifest

Two changes from the earlier draft, both falling out of "the generator owns the whole package":

**No `modules/lsp` workspace member.** The earlier plan put generated types in a new module so
they could be reused. Nothing needs to reuse them — and the module would have to be
`output-type = "static"`, because generated LSP types are *nothing but* a serialization path
full of `Array<T>` fields, the exact shape that trips cjc 1.1.3's `funcTable is nullptr`
abort across a shared-library boundary (CLAUDE.md, and the draft said `dynamic`, which would
have SIGABRT'd at runtime with a message naming stdx). A subpackage of the `cjls` executable
has no library boundary to lose the funcTable across, so the landmine is not merely defused
but unrepresentable. If a second consumer ever appears, promoting the directory to a module is
a regeneration with different flags.

**No `.lsp_codegen_manifest`.** The manifest existed so hand-written code could share the
directory; nothing hand-written lives there any more. Stale files are pruned by **header
ownership** instead: a run deletes every `.cj` in the output directory that carries the
`// Code generated by lsp_codegen` first line and was not written by this run. No sidecar file
to drift out of sync, and — unlike wiping the directory — it can never delete something a
person wrote, including if `--src-dir` is pointed somewhere wrong.

**Dependencies are the module's, not the package's.** A Cangjie subpackage has no `cjpm.toml`
of its own, so the generator cannot declare what it needs; `modules/cjls/cjpm.toml` gains
`stdxx = { path = "../stdxx" }` once, by hand, as a build-order step. `cjls.lsp_types`
deliberately does **not** import `jsonrpc` — types know nothing about transports, and that
stays a real constraint even though both now live under one module.

### Foreign types in the generated API

The generated API is full of `stdxx` and `stdx.serialization` types, and the mechanism for
that is the ordinary one: **every generated file opens with plain `import` lines.**

```cangjie
package cjls.lsp_types

import stdxx.*
import stdx.serialization.serialization.*
```

That is all the generated declarations need — `IntegerOrString`, `Nullable<T>`, `Serializable`
and `DataModel` are in scope and usable in any `*Params` struct, alias or `extend` the emitter
writes. Verified: a subpackage importing a foreign module this way compiles and runs, and its
consumers can construct the generated types, pass them around and call their methods without
importing that module themselves.

The one thing it does **not** cover is a consumer that *names* a foreign type directly —
`match`ing a `ProgressToken`, constructing a `Nullable.Value(x)`. That needs `import stdxx.*`
in the consumer's own file, which is one line and entirely normal Cangjie. `cjls` will be
doing that anyway.

**The reuse is deliberate.** `ProgressToken` is `integer | string`, structurally
`stdxx.IntegerOrString` — the same type `jsonrpc` already uses for `RequestId`. Emitting a
private twin would mean `CancelParams.id` could not be handed to `Connection`'s cancellation
without a pointless conversion, when the spec means them to be the same thing. Same for
`Nullable<T>`, which is how CLAUDE.md's nullable axis is modelled.

> Available but **not adopted**: `public import stdxx.IntegerOrString` in `aliases.cj` would
> re-export the name so consumers need no `stdxx` import at all (verified to work, including
> for `Serializable`'s `extend`-supplied members). It is pure ergonomics — it saves one import
> line — in exchange for a list of re-exports to keep in sync with what the emitter
> references. Not worth the machinery. Revisit only if the import turns out to be a real
> nuisance in practice.

## Type mapping

Mechanical, no judgment per field.

| metaModel | Cangjie |
|---|---|
| `string` | `String` |
| `DocumentUri` (28 uses), `URI` (9) | `DocumentUri` / `URI`, both `= String` aliases, see *URIs* |
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

### Identifiers — raw identifiers, no renames

**The generated name is the spec's name.** Where the spec's name is a Cangjie keyword, the
generator escapes it with backticks; it never invents a different one. Verified against
`cjc` 1.1.3 — raw identifiers work in every position the generator needs, including the two
this document previously called impossible:

```cangjie
public struct ShowMessageParams {
    public ShowMessageParams(public let `type`!: MessageType, public let message!: String) {}
}
let p = ShowMessageParams(`type`: MessageType.Error, message: "boom")   // named argument
println(p.`type`)                                                       // member access

public enum StringOrInteger { | `String`(String) | `Int32`(Int32) }     // payload constructors
match (v) { case `Int32`(i) => …; case `String`(s) => … }                // patterns

public enum CompletionItemKind { | Text | `Unit` | `class` | `interface` }
```

Two rules survive, and both are about idiom rather than collisions:

1. **Normalize case.** Enumeration value names become `UpperCamelCase` (`import` → `Import`,
   `asIs` → `AsIs`, `file` → `File`); open-enumeration constants become `UPPER_SNAKE_CASE`
   (`class` → `CLASS`). Property names are already `lowerCamelCase` and are left alone. This
   is a casing convention worth having on its own; that it also clears 9 of the 10 keyword
   collisions is now a side effect rather than the point.
2. **Spell out primitive union members** — `string → String`, `integer → Integer`,
   `uinteger → UInteger`, `decimal → Decimal`, `boolean → Boolean`. This one is *not* a
   keyword workaround (`` `Int32`(Int32) `` compiles fine). A union constructor has no wire
   name to be faithful to — the JSON carries no discriminator for it — so there is nothing
   fidelity could mean here, and `stdxx.IntegerOrString` already names them exactly this way.

**Escaping replaces the rename table.** What used to survive rules 1–2 was five declarations
needing hand-chosen names (`type` → `messageType`, `Unit` → `UnitKind`); those are now
`` `type` `` and `` `Unit` ``. The config table loses its rename column entirely.

**And it replaces the guard.** `emit` carries the keyword list and backticks anything on it,
mechanically. The old design hard-failed on an unlisted collision so a human could add a
name — that failure mode is gone: a metaModel bump introducing a new keyword-named property
regenerates cleanly instead of stopping the generator.

The trade, stated honestly: backticks are noise at every call site
(`` params.`type` ``, `` case `Unit` ``). What buys it back is that the names now match the
spec exactly — reading LSP documentation and reading the generated code no longer require a
translation table, `grep type` finds what the spec calls `type`, and nobody has to decide
whether `changeType` or `messageType` was the better invention. For generated wire types,
fidelity beats prettiness.

**Consequence for serde.** Property names are now always identical to their wire names, so
the emitted `serialize`/`deserialize` can use one string for both. `FieldIr` still carries
`name` and `wireName` separately, because *enumeration values* genuinely diverge — rule 1
title-cases the name while the wire `value` is whatever the spec says — and because the
backtick is a spelling of the emitted identifier, never part of the JSON key.

### URIs

`DocumentUri` and `URI` are **base types** in the metaModel — not `typeAliases`, so the
generator has to introduce the names itself. It emits them into `aliases.cj` as exactly what
the spec says they are:

```cangjie
public type DocumentUri = String
public type URI = String
```

An earlier draft wrapped `stdx.encoding.url.URL` to get a parsed scheme and decoded path.
**That belongs to the domain layer, not here.** This package is transport: its job is to move
the client's bytes in and out without editing them. Parsing is a separate concern with a
separate lifetime — a document store wants a normalized key, a file-watcher wants a path,
neither is a property of the wire message — and pushing it down here would have made every
consumer pay for it.

Three concrete costs, on top of the layering argument:

- `URL.parse` **throws**. Parsing on the deserialize path means a URI the server merely
  disagrees with fails the *whole enclosing message*, at the transport layer, where the only
  honest answer is a parse error about a field that was a perfectly well-formed JSON string.
- `toString()` normalizes dot segments, but LSP requires echoing the client's URI back
  **verbatim**. So the wrapper's identity, equality and serialization would all have had to be
  the raw string anyway — `url` was a cached accessor bolted to a `String`, which is a domain
  concern wearing a transport type's clothes.
- `URL` is neither `Hashable` nor `Equatable`, and servers key documents by URI in a `HashMap`
  constantly. `String` is both, for free.

The alias is transparent, so it buys naming and documentation value rather than type safety.
That is the correct trade for a generated wire type: it matches the metaModel exactly, costs
nothing at any call site, and leaves the domain layer free to define whatever validated
`DocumentUri` newtype it actually wants on top.

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
  values (`class`, `enum`, `interface`, `macro`, `operator`, `struct`, `type`) need no
  escaping — `CLASS`, `ENUM`, … are not keywords.

```cangjie
public enum CompletionItemKind {
    | Text | Method | Function /* … */ | `Unit` /* escaped: `Unit` is a keyword */
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

`String` is a library type, not a keyword, and `stdxx` already declares exactly this shape.
`integer` and `boolean` members are `Integer(Int32)` and `Boolean(Bool)` by rule 2 — a
choice of convention, not a workaround, since `` `Int32`(Int32) `` would compile.

**Naming.** Canonical name is structural — member names joined with `Or`, primitives spelled
out, arrays pluralised (`Location | [Location]` → `LocationOrLocations`) — which dedups the 93
occurrences down to 73 types automatically. When a `typeAlias` has exactly that definition,
the **alias name wins** (`Definition`, `TextDocumentContentChangeEvent`, `PrepareRenameResult`…)
and further aliases with the same structure become `public type Declaration = Definition`.
The config table holds structural-name overrides for the handful that read badly, without
touching the algorithm. Union names are the generator's own invention — no wire name
corresponds to them — so overriding one costs no fidelity, which is exactly why this table
survives while the property-rename table did not.

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
public interface LspRequestSpec<P, R> {
    static prop method: String
    static prop direction: MessageDirection
}

public struct ImplementationRequest <: LspRequestSpec<ImplementationParams, Nullable<DefinitionOrDefinitionLinks>> {
    public static prop method: String { get() { "textDocument/implementation" } }
    public static prop direction: MessageDirection { get() { MessageDirection.ClientToServer } }
    public static prop registrationMethod: String { get() { "textDocument/implementation" } }
}
```

**`static prop`, not `static const`** — an interface body rejects a variable declaration
outright (*"unexpected variable declaration in interface body"*), so `static const METHOD`
cannot be part of the contract at all. `static prop` can, and it carries the full weight:
declared in the interface, implemented in the struct, reachable as `ImplementationRequest.method`,
and — the part that matters for the router — reachable as `S.method` inside
`func f<S, P, R>() where S <: LspRequestSpec<P, R>`, with no instance in existence. Verified
by compiling and running exactly that, including `match`ing on a `static prop`-typed enum.

`prop` over `static func`: these are constants, so `S.method` should read as data rather than
as a call, and a `prop` without `mut` is immutable by construction. The verbosity of the
getter is generated text nobody types.

The spec structs are pure **type-level tags** — never instantiated, so the generator emits no
constructor. Only `method` and `direction` are universal enough to sit in the interface;
`partialResult`, `errorData` and `registrationOptions` exist on some requests and not others,
so forcing them into generic parameters would give every spec a four-parameter interface
mostly filled with placeholders. They are emitted as plain `static prop`s on the concrete
struct where the metaModel has them, and the registration macros reference them only where
they apply.

`LspRequestSpec<P, R>` / `LspNotificationSpec<P>` / `MessageDirection` are the seam the
`cjls.macros` handler registration binds against. They are **emitted from a fixed template**
into `spec.cj` — generated, but not derived from the metaModel.

That is forced, not stylistic: `cjls` imports `cjls.lsp_types`, so `cjls.lsp_types` cannot
import `cjls` back without a package cycle. The interfaces have to live either inside the
generated package or in a third one both can see. Inside is the better of the two — it is a
dozen lines that only ever change together with the emitter that targets them, and it keeps
the package importable on its own, which is the whole point of generating a complete
subpackage.

Everything else in `messages.cj` is data: method string, direction,
params/result/partialResult/errorData/registrationOptions types. Routing stays entirely in
`cjls`; `cjls.lsp_types` learns method names, `jsonrpc` still learns none.


## Generator internals

Four phases, one package (`lsp_codegen`, flat file layout — it is an executable, not a
library):

```
main.cj          std.argopt CLI → Config
config.cj        Config: metaModelPath, srcDir, outputPackage, the union-name overrides and
                 reuse table; derives the output dir from srcDir + outputPackage, validates
                 against the module's cjpm.toml
meta_model.cj    metaModel schema as Cangjie types, parsed via stdx.serialization DataModel
resolve.cj       metaModel → IR: flatten extends/mixins, lift literals, collect + name unions,
                 resolve aliases, pick a discrimination strategy per union
ir.cj            TypeIr / StructIr / EnumIr / UnionIr / FieldIr / MessageIr — every named
                 thing carries both its Cangjie name and its wire name
naming.cj        case normalization, keyword escaping (backticks, from the keyword list),
                 snake_case filenames, union naming
writer.cj        indent-aware SourceWriter (text), plus the stdx.syntax parseFile gate
                 applied to each written file — see Emission below
emit_*.cj        emit_struct / emit_enum / emit_union / emit_message / emit_serde / emit_docs
preamble.cj      the fixed-template files: aliases.cj (base types) and spec.cj (the seam
                 interfaces), plus the import block every emitted file opens with —
                 generated, but not derived from the metaModel
output.cj        write outputs, then prune every generated-header .cj this run did not write
```

Phase separation is the point: `resolve` makes every decision (names, nullability,
discriminators, ordering) and `emit_*` does no thinking. That keeps naming and mapping rules
unit-testable without touching text output, and makes the emitters small enough to review.

### Emission: a text writer, gated by `stdx.syntax` parsing

**Decision: `SourceWriter` emits text; `stdx.syntax` then parses every written file as a
validation gate.** Measured on cjc 1.3.0, where `stdx.syntax` links and runs.

`stdx.syntax` was the front-runner for the emitter itself, because comments are structural
node properties rather than lexer trivia — upstream's `rewrite.md` attaches a `Comment` via a
`comments:` argument, and that verifiably works: a constructed `Comment` renders on its own
line above its declaration. The fidelity test disqualified it anyway, and the reason is worth
recording because it is not obvious:

**Rendering is position-preserving, not layout-synthesising.** Nodes that came from a parse
render byte-identically — an identity rebuild (`StructDecl` reconstructed from its own
children) returns the original text exactly, indentation and all. Nodes constructed fresh have
no source position and get no layout. Attaching a new `Comment` to a field demonstrates both
halves at once:

```cangjie
public struct DefinitionParams {
    /** Inherited from `WorkDoneProgressParams`. */
public let textDocument: TextDocumentIdentifier = t     // ← lost its indentation
```

The comment lands correctly; the declaration it attached to drops to column 0. A generator
builds *everything* from scratch, so it would hit the no-position path on every node — this is
a rewriter library, excellent at transforming parsed code, not a pretty-printer for synthetic
trees.

**What it is excellent at is the gate.** `parseFile` handles comment-rich, multi-declaration
files and round-trips them byte-identically — verified on a file with struct docs, field docs
and a func doc. So after writing each file the generator parses it back, and a file that does
not parse fails the run with the real Cangjie parser's diagnostic, naming the file. That
catches emitter bugs per-file at generation time instead of as a wall of errors from
`cjpm build` across a 450-file tree, and it is strictly more than the original text-only
design had.

Use `parseFile`, not `parseText`: `parseText` rejects anything that is more than one node, and
*any* inline comment makes a declaration multi-node (`parseText function not support parse
more than one node`) — so it cannot validate the very files this generator produces.

#### Why not `std.ast`

An earlier draft justified rejecting it with "`quote(…)` buys nothing when there is no macro
expansion context". **That was wrong.** `quote(…)` compiles and runs in an ordinary
executable — no macro package required — and `Tokens.toString()` renders multi-line, indented
source ready to write to disk. Verified by building and running it.

The rejection stands on evidence instead. `Tokens.toString()` is a token *printer*, not a
formatter that honours intended layout. Emitting the *Structures* example through `quote`
produces:

```cangjie
public struct DefinitionParams { public DefinitionParams(/** Inherited from `WorkDoneProgressParams`. */
    public let workDoneToken!:?ProgressToken = None, /** Inherited from `PartialResultParams`. */
    public let partialResultToken!:?ProgressToken = None) { } }
```

Three defects, all verified rather than predicted: the struct body collapses onto one line;
`!:?ProgressToken` loses the space a person writes after `:`; and each doc comment attaches to
the tail of the *previous* line instead of sitting above its field. Getting from there to the
target layout means injecting `NL` tokens by hand at every boundary and still not being able
to fix `!:?` — which is text emission with extra steps and less control.

**Comments are the deciding factor.** The lexer discards them, so a comment written inside
`quote(/** doc */ public struct …)` simply vanishes from the output — confirmed, the tokens
are not there. They can be reintroduced as explicit `Token(TokenKind.COMMENT, …)` values
concatenated onto the `Tokens` (that works), but that means the most documentation-heavy part
of this generator — every `documentation`, `@since`, `@deprecated` and `Inherited from`
provenance note — is hand-plumbed token concatenation regardless. `quote`'s ergonomics do not
reach the part of the job that needs them most.

What `quote` genuinely offers, and this is worth naming since the old reason denied it: the
template is parsed by `cjc` when the *generator* is compiled, so a malformed template breaks
the generator build rather than producing a broken tree. Real, but weak here — heavy
`$`-interpolation means the holes accept any `Tokens`, and the *Compiles* test already proves
the much stronger property that the whole 450-type tree builds.

#### Linking `stdx.syntax`

It is **C++-backed** — flatbuffers plus the compiler frontend — so it is not a pure-Cangjie
dependency. `modules/lsp_codegen/cjpm.toml` needs:

```toml
link-option = "-lstdx.syntaxFFI -lc++"
```

Without `-lc++` the link fails on `std::__1::basic_string` and `__cxxabiv1::__class_type_info`,
which reads like a broken stdx rather than a missing flag. This cost is confined to
`lsp_codegen`; nothing else in the workspace links it.

Historical note, in case a version ever drifts again: on cjc 1.1.3 the same library failed to
link with *frontend* symbols missing — it wanted
`SourceManager::AddSource(…, optional<string>, bool)` where 1.1.3 provided the same function
without the trailing `bool`. That was an ABI mismatch between a stdx built for one compiler
and a different compiler installed, diagnosable from `third_party/stdx/package.json`, whose
`cjc_version` must match `cjc --version`. Both now read `1.3.0-alpha.20260804010019`.

`documentation` becomes a `/** … */` doc comment with `*/` escaped, `since` becomes
`@since`, `deprecated` becomes `@deprecated` (1 structure, plus properties).

**Determinism** is a hard requirement: metaModel order is preserved everywhere, maps are
iterated sorted, so regenerating produces a byte-identical tree and a real diff means a real
change.

## Testing

Matching the repo's conventions (`*_test.cj` beside the code, arrange/act/assert, sentence-named cases):

- **Unit** — `naming.cj` and `resolve.cj` are pure functions over small inputs: case
  normalization, keyword escaping (every name on the keyword list gets backticks, everything
  else is left alone), union naming and dedup, extends/mixins flattening with a redeclared
  property, the four optional/nullable combinations, discrimination-strategy selection per
  union shape.
- **Backticks never reach the wire** — assert that a struct with a `` `type` `` field
  serializes to the JSON key `type`, and that an escaped enum constructor round-trips to its
  unescaped wire value. Escaping is a spelling of Cangjie source; leaking one into a JSON key
  is the regression this design most invites.
- **Parses** — every emitted file is fed to `stdx.syntax`'s `parseFile` as part of the run
  itself (see *Emission*), so malformed output fails generation rather than the build. The
  golden tests get this for free.
- **Golden** — a trimmed fixture metaModel in `testdata/` (one struct with inheritance, one
  open and one closed enum, one union per discrimination strategy, one message) generated
  into a temp dir and compared against checked-in expected `.cj` text. Golden files are the
  review surface for "does this read like Cangjie".
- **Compiles** — generating the full 450-type tree and building `cjls` is the only
  proof the emitter is correct; run it in CI, not in `cjpm test`.
- **Round-trip** — in `cjls`, a corpus of real LSP payloads (an `initialize` request, a
  `textDocument/publishDiagnostics`, a completion list) deserialized → serialized →
  compared as `DataModel`. This is where union discrimination and the optional-vs-null
  distinction actually get exercised.

## Generated code is checked in

`modules/cjls/src/lsp_types` is committed in full, regenerated by hand when the metaModel is
bumped. It keeps the build free of a bootstrap dependency (`lsp_codegen` is itself built by
`cjpm`, and it would otherwise have to build before the module that contains it), makes the
emitter's output reviewable in PRs, and means a metaModel bump shows up as a diff rather than
as a silent behaviour change. A `pre-build` script (like `build.cj` does for `stdx`) stays
available if regeneration ever becomes routine.

Committing it is also what makes the "whole subpackage" contract checkable: the tree in git is
the artifact, so a reviewer sees the aliases, the specs and the 450 types as one package
rather than as emitter source they have to run in their head.

## Build order

0. ~~`stdxx`: promote `getOrNone` to public~~ — **done**, `modules/stdxx/src/data_model.cj`.
1. ~~Toolchain: cjc → 1.3.0, all four `cjpm.toml` pins bumped, suite green (243 tests)~~ —
   **done**. Both open measurements settled: `stdx.syntax` links and is used as a gate rather
   than an emitter (*Emission*); the `funcTable` abort no longer reproduces (*Cangjie facts*).
2. `modules/cjls/cjpm.toml` gains `stdxx = { path = "../stdxx" }`; `modules/lsp_codegen`
   gains `link-option = "-lstdx.syntaxFFI -lc++"`. The first is not optional: `cjls` depends
   on `jsonrpc` which depends on `stdxx`, but cjpm deps are not transitive (verified above),
   so without it the first generated `import stdxx.*` fails the build.
3. `lsp_codegen`: config + output-dir derivation + cjpm.toml validation + header-based
   pruning, then emit `aliases.cj`, `spec.cj` and the **enumerations** end to end.
   Smallest slice that proves the pipeline and the whole-package contract at once.
4. Structures + `Serializable` emission (the bulk: 387 types).
5. Unions + discrimination strategies.
6. Messages.
7. Reintroduce `@LspRequest`/`@LspHandlers` in `cjls` against the generated specs.

Steps 3–6 each end with `cjpm build` green, so the emitter is never more than one category
ahead of proof that it works.
