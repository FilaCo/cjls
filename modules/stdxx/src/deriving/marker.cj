macro package stdxx.deriving

import std.ast.*
import std.collection.*

const MARKER_MACRO = "DeriveExtSerializable"
const ITEM_IDENT = "ident"
const ITEM_ON_TYPE = "onType"
const ITEM_RENAME = "rename"
const ITEM_SKIP_NONE = "skipNone"
const ITEM_TRANSPARENT = "transparent"
const ITEM_TAG = "tag"
const ITEM_VALUE = "value"
const ITEM_VALUE_IS_INTEGER = "valueIsInteger"
const ITEM_PAYLOAD = "payload"
const ITEM_OTHER = "other"

/**
 * Configures what `@DeriveExt[Serializable]` generates for the declaration it sits on - one marker
 * for every position.
 *
 * Which options are legal follows from where it sits:
 *
 * | on          | option                    | meaning                                             |
 * |-------------|---------------------------|-----------------------------------------------------|
 * | type        | `skipNone`                | every optional field omits its key when `None`      |
 * | type        | `tag: "kind"`             | the type is internally tagged by that field         |
 * | struct      | `value: "delete"`         | the tag's value - required with `tag` on a struct   |
 * | type        | `transparent`             | the struct is its only field on the wire            |
 * | field       | `rename: "textDocument"`  | the name the field carries on the wire              |
 * | field       | `skipNone`                | this field omits its key when `None`                |
 * | enum variant| `value: "URI"`, `value: -1`| what the variant is on the wire, or its tag        |
 * | enum variant| `payload: ["key"]`        | the names of the variant's positional payload       |
 * | enum variant| `other`                   | any value no other variant claims, kept as payload  |
 *
 * ```
 * @DeriveExt[Serializable]
 * @DeriveExtSerializable[skipNone]
 * public struct Edit {
 *     public Edit(
 *         @DeriveExtSerializable[rename: "textDocument"] let document!: String,
 *         let edits!: ?Array<String> = None
 *     ) {}
 * }
 * ```
 *
 * Anything not given falls back to the declaration itself: a field is named by its own identifier
 * with the backquotes stripped, a variant is its identifier as a string.
 *
 * @note it is only legal inside `@DeriveExt` - it carries its options to the enclosing macro and
 *       expands to nothing of its own.
 */
public macro DeriveExtSerializable(attrs: Tokens, input: Tokens): Tokens {
    assertParentContext(DERIVE_EXT_MACRO)

    let position = positionOf(input)
    let ident = identOf(input) ?? Token(TokenKind.IDENTIFIER, "")
    setItem(ITEM_IDENT, ident.value)
    setItem(ITEM_ON_TYPE, "${position.isType}")

    match (parseExpr(quote(dummy($attrs)))) {
        case call: CallExpr => for (argument in call.arguments) {
            applyOption(argument, position)
        }
        case _ => diagReport(
            DiagReportLevel.ERROR,
            attrs,
            "`@DeriveExtSerializable` takes named options",
            "e.g. `@DeriveExtSerializable[rename: \"textDocument\", skipNone]`"
        )
    }

    input
}

/**
 * Where a marker sits, which is what decides the options it may carry. Read off the declaration it
 * was given: a type opens with its keyword, a field with `let` or `var`, and what is left in an
 * enum body is a constructor.
 */
enum MarkerPosition {
    | OnType
    | OnField
    | OnVariant

    prop isType: Bool {
        get() {
            match (this) {
                case OnType => true
                case _ => false
            }
        }
    }

    prop name: String {
        get() {
            match (this) {
                case OnType => "a type"
                case OnField => "a field"
                case OnVariant => "an enum variant"
            }
        }
    }
}

private func positionOf(input: Tokens): MarkerPosition {
    let head = headTokenOf(input) ?? return OnVariant

    match (head.kind) {
        case TokenKind.STRUCT | TokenKind.CLASS | TokenKind.ENUM => OnType
        case TokenKind.LET | TokenKind.VAR => OnField
        case _ => OnVariant
    }
}

private func applyOption(argument: Argument, position: MarkerPosition): Unit {
    let tokens = argument.toTokens()
    let name = tokens[0].value
    let isFlag = !(tokens.size >= 2 && tokens[1].kind == TokenKind.COLON)
    let value = argument.expr.toTokens()

    match (name) {
        case "rename" =>
            if (expected(argument, position, [OnField], isFlag, false)) {
                setStringOption(argument, ITEM_RENAME, value)
            }
        case "tag" =>
            if (expected(argument, position, [OnType], isFlag, false)) {
                setStringOption(argument, ITEM_TAG, value)
            }
        case "transparent" =>
            if (expected(argument, position, [OnType], isFlag, true)) {
                setItem(ITEM_TRANSPARENT, "true")
            }
        case "skipNone" =>
            if (expected(argument, position, [OnType, OnField], isFlag, true)) {
                setItem(ITEM_SKIP_NONE, "true")
            }
        case "value" =>
            if (expected(argument, position, [OnVariant, OnType], isFlag, false)) {
                setWireValueOption(argument, value)
            }
        case "other" =>
            if (expected(argument, position, [OnVariant], isFlag, true)) {
                setItem(ITEM_OTHER, "true")
            }
        case "payload" =>
            if (expected(argument, position, [OnVariant], isFlag, false)) {
                setPayloadOption(argument, value)
            }
        case _ => diagReport(
            DiagReportLevel.ERROR,
            tokens,
            "`@DeriveExtSerializable` has no option `${name}`",
            "it takes: rename, skipNone, tag, transparent, value, payload, other"
        )
    }
}

/**
 * Whether the option is where it belongs and spelled the way it takes its argument - a flag on its
 * own, anything else as `name: value`.
 */
private func expected(
    argument: Argument,
    position: MarkerPosition,
    positions: Array<MarkerPosition>,
    isFlag: Bool,
    wantsFlag: Bool
): Bool {
    let tokens = argument.toTokens()
    let name = tokens[0].value

    let names = positions.map {allowed => allowed.name}
    if (!names.contains(position.name)) {
        diagReport(
            DiagReportLevel.ERROR,
            tokens,
            "`${name}` does not apply to ${position.name}",
            "it belongs on ${String.join(names, delimiter: " or ")}"
        )
        return false
    }

    if (isFlag != wantsFlag) {
        let (spelling, hint) = if (wantsFlag) {
            ("`${name}` is a flag", "spell it `${name}`, with no value")
        } else {
            ("`${name}` needs a value", "spell it `${name}: ...`")
        }
        diagReport(DiagReportLevel.ERROR, tokens, spelling, hint)
        return false
    }

    true
}

private func setStringOption(argument: Argument, item: String, value: Tokens): Unit {
    if (value.size != 1 || value[0].kind != TokenKind.STRING_LITERAL) {
        diagReport(
            DiagReportLevel.ERROR,
            argument.toTokens(),
            "`${argument.toTokens()[0].value}` takes a string literal",
            "e.g. `${argument.toTokens()[0].value}: \"textDocument\"`"
        )
        return
    }

    setItem(item, value[0].value)
}

private func setWireValueOption(argument: Argument, value: Tokens): Unit {
    if (value.size == 1 && value[0].kind == TokenKind.STRING_LITERAL) {
        setItem(ITEM_VALUE, value[0].value)
        setItem(ITEM_VALUE_IS_INTEGER, "false")
        return
    }

    match (integerTextOf(value)) {
        case Some(text) =>
            setItem(ITEM_VALUE, text)
            setItem(ITEM_VALUE_IS_INTEGER, "true")
        case None => diagReport(
            DiagReportLevel.ERROR,
            argument.toTokens(),
            "`value` takes a string or an integer literal",
            "e.g. `value: \"URI\"`, `value: 1` or `value: -32700`"
        )
    }
}

/**
 * A negative literal reaches a macro as two tokens - the sign is an operator, not part of the
 * number - so it has to be put back together here and taken apart again on the way out.
 */
private func integerTextOf(tokens: Tokens): ?String {
    if (tokens.size == 1 && tokens[0].kind == TokenKind.INTEGER_LITERAL) {
        return tokens[0].value
    }
    if (tokens.size == 2 && tokens[0].kind == TokenKind.SUB && tokens[1].kind == TokenKind.INTEGER_LITERAL) {
        return "-${tokens[1].value}"
    }

    None
}

private func setPayloadOption(argument: Argument, value: Tokens): Unit {
    let names = value |> filter {token: Token => token.kind == TokenKind.STRING_LITERAL} |>
        map {token: Token => token.value} |> collectArray

    if (names.isEmpty()) {
        diagReport(
            DiagReportLevel.ERROR,
            argument.toTokens(),
            "`payload` takes the payload's field names as string literals",
            "e.g. `payload: [\"key\", \"value\"]`"
        )
        return
    }

    setItem(ITEM_PAYLOAD, String.join(names, delimiter: ","))
}

/**
 * A value a variant carries on the wire, as the literal to emit and the base type it implies.
 *
 * @note the literal is `Tokens`, not one `Token`: a negative integer is a `-` followed by the
 *       number, and emitting it as a single token with the sign baked into its text is rejected
 *       by the macro expander.
 */
struct WireValue {
    WireValue(let literal!: Tokens, let text!: String, let isInteger!: Bool) {}

    static func ofString(value: String): WireValue {
        WireValue(literal: Tokens(Token(TokenKind.STRING_LITERAL, value)), text: value, isInteger: false)
    }

    static func of(text: String, isInteger: Bool): WireValue {
        if (!isInteger) {
            return ofString(text)
        }

        var literal = Tokens()
        var digits = text
        if (text.startsWith("-")) {
            literal += Tokens(Token(TokenKind.SUB, "-"))
            digits = text[1..text.size]
        }
        literal += Tokens(Token(TokenKind.INTEGER_LITERAL, digits))

        WireValue(literal: literal, text: text, isInteger: true)
    }
}

/**
 * Everything one marker asked for.
 */
struct MarkerOptions {
    MarkerOptions(
        let rename!: ?String = None,
        let skipNone!: Bool = false,
        let tag!: ?String = None,
        let transparent!: Bool = false,
        let value!: ?WireValue = None,
        let payload!: Array<String> = [],
        let other!: Bool = false
    ) {}
}

/**
 * What the `@DeriveExtSerializable` children of the current `@DeriveExt` asked for: the options of
 * the type itself, and those of each of its fields or variants by identifier.
 */
func collectMarkers(): (MarkerOptions, HashMap<String, MarkerOptions>) {
    var typeOptions = MarkerOptions()
    let memberOptions = HashMap<String, MarkerOptions>()

    for (message in getChildMessages(MARKER_MACRO)) {
        let options = optionsOf(message)
        if (message.getString(ITEM_ON_TYPE) == "true") {
            typeOptions = options
        } else {
            memberOptions[message.getString(ITEM_IDENT)] = options
        }
    }

    (typeOptions, memberOptions)
}

private func optionsOf(message: MacroMessage): MarkerOptions {
    MarkerOptions(
        rename: stringItemOf(message, ITEM_RENAME),
        skipNone: message.hasItem(ITEM_SKIP_NONE),
        tag: stringItemOf(message, ITEM_TAG),
        transparent: message.hasItem(ITEM_TRANSPARENT),
        value: stringItemOf(message, ITEM_VALUE).map {
            value => WireValue.of(value, message.getString(ITEM_VALUE_IS_INTEGER) == "true")
        },
        payload: stringItemOf(message, ITEM_PAYLOAD).map {payload => payload.split(",")} ?? [],
        other: message.hasItem(ITEM_OTHER)
    )
}

private func stringItemOf(message: MacroMessage, key: String): ?String {
    if (message.hasItem(key)) {
        message.getString(key)
    } else {
        None
    }
}
