package cjls_interface

import cjls_db.CangjieLanguageServerDatabase

public func runServer<R>(f: (CangjieLanguageServerDatabase) -> R): R {
    f(CangjieLanguageServerDatabaseImpl())
}
