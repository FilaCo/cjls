package cjls

main(): Unit {
    initGlobalLogger()

    try {
        runServer()
    } catch (e: ProtocolStateException) {
        logError("protocol error, shutting down: ${e.message}")
    } catch (e: Exception) {
        logFatal("something went wrong, shutting down: ${e}")
    }
}
