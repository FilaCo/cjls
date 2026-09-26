import asyncio

import psutil
from lsprotocol import types
from pytest_lsp import LanguageClient

from test_documents import open_document, outline

# enough allocation for the runtime to start a garbage collection
FILES = 5
TEXT = "class A {\n" + "    func f(x: Int64): Int64 { x + 1 }\n" * 2000 + "}\n"


async def test_a_server_waiting_for_input_uses_no_cpu(client: LanguageClient):
    # arrange: work that leaves garbage behind, then nothing more from the client
    for i in range(FILES):
        open_document(client, f"untitled:{i}", TEXT)
        assert await outline(client, f"untitled:{i}")
    process = psutil.Process(client._server.pid)

    # act: this measures being idle, so it can only take time
    before = process.cpu_times()
    await asyncio.sleep(2)
    after = process.cpu_times()

    # assert: a collection used to wait for the thread blocked reading stdin with a `read` cjc
    # compiled as @FastNative, at full CPU, until the client next wrote (D13)
    used = (after.user - before.user) + (after.system - before.system)
    assert used < 0.5, f"{used:.2f}s of CPU in 2s of waiting"
