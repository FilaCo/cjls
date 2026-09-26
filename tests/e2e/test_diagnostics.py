"""Diagnostics as the two kinds of client get them (D14): what the unit tests cannot see is a real client's
capabilities choosing the path, and the push arriving over stdio. The cases themselves are unit tests (C7)."""

import asyncio

from lsprotocol import types
from pytest_lsp import LanguageClient, client_capabilities
from test_documents import open_document

# one parser error: "expected '{'", where the body should start
BROKEN = "func noBody(): Unit"
BROKEN_AT = types.Position(line=0, character=19)
FIXED = "func noBody(): Unit {}"


def change_whole(client: LanguageClient, uri: str, text: str, version: int):
    client.text_document_did_change(
        types.DidChangeTextDocumentParams(
            text_document=types.VersionedTextDocumentIdentifier(uri=uri, version=version),
            content_changes=[types.TextDocumentContentChangeWholeDocument(text=text)],
        )
    )


async def pull(client: LanguageClient, uri: str) -> list[types.Diagnostic]:
    report = await client.text_document_diagnostic_async(
        types.DocumentDiagnosticParams(text_document=types.TextDocumentIdentifier(uri=uri))
    )
    assert report.kind == types.DocumentDiagnosticReportKind.Full
    return report.items


async def pushed_after(client: LanguageClient, send) -> types.PublishDiagnosticsParams:
    """What the server publishes after `send()`: waiting starts before it, so a quick answer is not missed."""
    publish = asyncio.wrap_future(client.protocol.wait_for_notification(types.TEXT_DOCUMENT_PUBLISH_DIAGNOSTICS))
    send()
    return await asyncio.wait_for(publish, timeout=10)


def assert_the_broken_body(diagnostics: list[types.Diagnostic]):
    assert len(diagnostics) == 1
    d = diagnostics[0]
    assert d.severity == types.DiagnosticSeverity.Error
    assert d.source == "cjls"
    assert d.range.start == BROKEN_AT
    assert d.message


async def test_a_client_that_pulls_sees_the_errors_until_the_document_is_fixed(server: LanguageClient):
    # arrange: Neovim pulls
    await server.initialize_session(types.InitializeParams(capabilities=client_capabilities("neovim")))
    uri = "untitled:a"
    open_document(server, uri, BROKEN)
    assert_the_broken_body(await pull(server, uri))

    # act
    change_whole(server, uri, FIXED, version=2)

    # assert
    assert await pull(server, uri) == []

    await server.shutdown_session()


async def test_a_client_that_cannot_pull_is_pushed_the_errors_and_their_clearing(server: LanguageClient):
    # arrange: Emacs' eglot knows only push
    await server.initialize_session(types.InitializeParams(capabilities=client_capabilities("emacs")))
    uri = "untitled:a"

    # act
    opened = await pushed_after(server, lambda: open_document(server, uri, BROKEN))
    closed = await pushed_after(
        server,
        lambda: server.text_document_did_close(
            types.DidCloseTextDocumentParams(text_document=types.TextDocumentIdentifier(uri=uri))
        ),
    )

    # assert
    assert opened.uri == uri
    assert_the_broken_body(opened.diagnostics)
    assert closed.uri == uri
    assert closed.diagnostics == []

    await server.shutdown_session()
