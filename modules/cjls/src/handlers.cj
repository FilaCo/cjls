package cjls

import cjls.macros.*

@LspHandlers[
    notifications: [
        DidOpenTextDocument
    ]
]
class Handlers {}