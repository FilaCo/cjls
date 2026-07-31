package stdxx

/**
 * Raised by the `get*OrThrow` accessors of a sum type when the value holds a
 * different variant than the one asked for. This is a programmer error, not a
 * recoverable condition - check with the matching `is*` predicate first.
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
