"""End-to-end tests: the built `cjls` binary, driven over stdio as an editor drives it.

The binary is target/release/bin/cjls (`cjls.exe` on Windows); CJLS_BIN overrides it.
"""

import asyncio
import os
import pathlib
import sys

import pytest_lsp
from lsprotocol import types
from pytest_lsp import ClientServerConfig, LanguageClient, client_capabilities

REPO = pathlib.Path(__file__).resolve().parents[2]
CJLS = os.environ.get("CJLS_BIN") or str(
    REPO / "target" / "release" / "bin" / ("cjls.exe" if sys.platform == "win32" else "cjls")
)
CONFIG = ClientServerConfig(server_command=[CJLS])

# the capabilities of real editors, as pytest-lsp captured them
CLIENTS = ["visual-studio-code", "neovim"]


async def hang_up(client: LanguageClient):
    """Ends a server a failed test left running: pygls' `stop` would wait for it forever."""
    server = client._server
    if server is None or server.returncode is not None:
        return
    server.stdin.close()
    try:
        await asyncio.wait_for(server.wait(), timeout=5)
    except TimeoutError:
        server.kill()
        await server.wait()


@pytest_lsp.fixture(config=CONFIG, params=CLIENTS)
async def client(request, lsp_client: LanguageClient):
    """A session initialized with the capabilities of a real editor, shut down afterwards.

    `position_encoding` holds the encoding the two agreed on.
    """
    result = await lsp_client.initialize_session(
        types.InitializeParams(capabilities=client_capabilities(request.param))
    )
    lsp_client.position_encoding = result.capabilities.position_encoding
    yield
    try:
        await lsp_client.shutdown_session()
    finally:
        await hang_up(lsp_client)


@pytest_lsp.fixture(config=CONFIG)
async def server(lsp_client: LanguageClient):
    """A server just started: the test takes it through its lifecycle itself."""
    yield
    await hang_up(lsp_client)
