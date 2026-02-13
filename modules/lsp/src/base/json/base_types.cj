package lsp.base.json

import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue, JsonFloat, JsonInt}

/**
 * Defines an integer number in the range of -2^31 to 2^31 - 1.
 */
public type LspInteger = JsonInt

/**
 * Defines an unsigned integer number in the range of 0 to 2^31 - 1.
 */
public type LspUInteger = JsonInt

/**
 * Defines a decimal number. Since decimal numbers are very
 * rare in the language server specification we denote the
 * exact range with every decimal using the mathematics
 * interval notation (e.g. [0, 1] denotes all decimals d with
 * 0 <= d <= 1.
 */
public type LspDecimal = JsonFloat

/**
 * The LSP any type.
 */
public type LspAny = JsonValue

/**
 * LSP object definition.
 */
public type LspObject = JsonObject

/**
 * LSP arrays.
 */
public type LspArray = JsonArray

/**
 * LSP string.
 */
public type LspString = JsonString

/**
 * LSP `integer | string` type.
 */
public enum IntegerOrString {
    Integer(LspInteger) | String(LspString)
}
