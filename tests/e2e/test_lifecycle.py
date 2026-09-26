import pytest
from lsprotocol import types
from pygls.exceptions import JsonRpcException
from pygls.protocol import JsonRPCProtocol
from pytest_lsp import LanguageClient

SERVER_NOT_INITIALIZED = -32002


def exit_code(client: LanguageClient) -> int | None:
    return client._server.returncode


async def test_initialize_tells_what_the_server_can_do(server: LanguageClient):
    # act
    result = await server.initialize_session(
        types.InitializeParams(capabilities=types.ClientCapabilities())
    )

    # assert
    assert result.server_info is not None and result.server_info.name == "cjls"
    assert result.capabilities.position_encoding == types.PositionEncodingKind.Utf16
    assert result.capabilities.document_symbol_provider is True
    diagnostics = result.capabilities.diagnostic_provider
    assert diagnostics.inter_file_dependencies is False
    assert diagnostics.workspace_diagnostics is False
    sync = result.capabilities.text_document_sync
    assert sync.open_close is True
    assert sync.change == types.TextDocumentSyncKind.Incremental

    await server.shutdown_session()


async def test_exit_after_shutdown_ends_the_process_with_0(server: LanguageClient):
    # arrange
    await server.initialize_session(types.InitializeParams(capabilities=types.ClientCapabilities()))

    # act: sends shutdown, then exit, and waits for the process
    await server.shutdown_session()

    # assert
    assert exit_code(server) == 0


async def test_exit_without_shutdown_ends_the_process_with_1(server: LanguageClient):
    # arrange
    await server.initialize_session(types.InitializeParams(capabilities=types.ClientCapabilities()))

    # act
    server.exit(None)
    await server._server.wait()

    # assert
    assert exit_code(server) == 1


async def test_a_request_before_initialize_is_refused(server: LanguageClient):
    # arrange: past pytest-lsp, which refuses to send anything before `initialize` itself
    params = types.DocumentSymbolParams(text_document=types.TextDocumentIdentifier(uri="file:///a.cj"))

    # act
    with pytest.raises(JsonRpcException) as refused:
        await JsonRPCProtocol.send_request_async(server.protocol, types.TEXT_DOCUMENT_DOCUMENT_SYMBOL, params)

    # assert
    assert refused.value.code == SERVER_NOT_INITIALIZED
