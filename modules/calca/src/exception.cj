package calca

/**
 * Thrown out of a query whose answer nobody needs any more: a write is waiting for it to end, or
 * its snapshot is of a revision gone by, and nothing it computes would be current; or whoever uses
 * the snapshot asked it to stop. Catch it where the handle is used, and drop the handle.
 */
public class Cancelled <: Exception {
    init() {
        super("the query was cancelled")
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
