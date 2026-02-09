package cjls

import stdx.log.getGlobalLogger
import cjls.utils.initGlobalLogger

main() {
    initGlobalLogger()
    let logger = getGlobalLogger([("name", "main")])
    logger.info("starting language server")
}
