package cjls

import stdx.log.getGlobalLogger

import cjls.utils.initGlobalLogger

main(): Int64 {
    initGlobalLogger()
    let logger = getGlobalLogger([("name", "main")])
    logger.info("starting language server")
    0
}
