package cjls

import stdx.log.getGlobalLogger

main(): Int64 {
    initGlobalLogger()
    try {
        runServer()
    } catch (e: Exception) {
        getGlobalLogger().fatal("server failed", [("cause", e)])
        1
    }
}
