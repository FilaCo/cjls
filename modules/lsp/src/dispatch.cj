package lsp

public interface LspRequest<P, R> {
    static func method(): String
}

public interface LspNotification<P> {
    static func method(): String
}
