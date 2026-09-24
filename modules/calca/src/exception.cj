package calca

/**
 * Thrown out of a query on a handle whose revision is being replaced: a write is waiting for every
 * other handle to close, and nothing it computes would be current any more. Catch it where the
 * handle is used, close the handle, and answer that the content was modified.
 */
public class Cancelled <: Exception {
    init() {
        super("a write is waiting for this handle to close")
    }

    protected func getClassName(): String {
        "Cancelled"
    }
}

/**
 * Thrown when a tracked function ends up needing its own result, directly or through others.
 */
public class CycleException <: Exception {
    init(message: String) {
        super(message)
    }

    protected func getClassName(): String {
        "CycleException"
    }
}
