package stdxx

/**
 * A `get*OrThrow` of a sum type asked for a variant the value does not hold - a programmer error,
 * not a condition to recover from.
 */
public class UnexpectedVariantException <: Exception {
    public init(expected: String, actual: String) {
        super("expected `${expected}` variant, got `${actual}`")
    }

    public init(message: String) {
        super(message)
    }

    protected override func getClassName(): String {
        "UnexpectedVariantException"
    }
}

public class NullValueException <: Exception {
    public init() {
        super("value is null")
    }

    public init(message: String) {
        super(message)
    }

    protected override func getClassName(): String {
        "NullValueException"
    }
}
