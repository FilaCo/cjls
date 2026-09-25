package stdxx

/**
 * A `get*OrThrow` of a sum type asked for a variant the value does not hold - a programmer error,
 * not a condition to recover from.
 */
public class UnexpectedVariantException <: Exception {
    public UnexpectedVariantException(message: String) {
        super(message)
    }

    public init(expected: String, actual: String) {
        this("expected `${expected}` variant, got `${actual}`")
    }

    protected override func getClassName(): String {
        "UnexpectedVariantException"
    }
}

public class NullValueException <: Exception {
    public NullValueException(message: String) {
        super(message)
    }

    public init() {
        this("value is null")
    }

    protected override func getClassName(): String {
        "NullValueException"
    }
}
