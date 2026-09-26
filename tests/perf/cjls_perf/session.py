"""One server process, driven over stdio as an editor drives it, and measured while it runs."""

import asyncio
import os
import pathlib
import threading
import time
from dataclasses import dataclass

import psutil
from lsprotocol import types
from pygls.lsp.client import LanguageClient

from .servers import Server
from .workspace import Workspace

MB = 1024 * 1024

# what an editor offers; nothing the servers would answer differently from Neovim or VS Code
CAPABILITIES = types.ClientCapabilities(
    general=types.GeneralClientCapabilities(position_encodings=[types.PositionEncodingKind.Utf16]),
    window=types.WindowClientCapabilities(work_done_progress=True),
    workspace=types.WorkspaceClientCapabilities(configuration=True, workspace_folders=True),
    text_document=types.TextDocumentClientCapabilities(
        synchronization=types.TextDocumentSyncClientCapabilities(did_save=True),
        document_symbol=types.DocumentSymbolClientCapabilities(hierarchical_document_symbol_support=True),
        publish_diagnostics=types.PublishDiagnosticsClientCapabilities(),
        diagnostic=types.DiagnosticClientCapabilities(),
    ),
)


@dataclass
class Usage:
    rss_mb: float
    peak_rss_mb: float
    cpu_s: float


class Sampler:
    """RSS and CPU of the server and every process under it, sampled on a thread of its own.

    The whole tree, because a server may be a launcher: R9's is a script starting `java`.
    """

    def __init__(self, pid: int, interval: float = 0.02):
        self.root = psutil.Process(pid)
        self.interval = interval
        self.peak = 0
        self.rss = 0
        self.cpu = 0.0
        self.stopped = threading.Event()
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()

    def tree(self) -> list[psutil.Process]:
        try:
            return [self.root, *self.root.children(recursive=True)]
        except psutil.Error:
            return []

    def sample(self):
        rss, cpu = 0, 0.0
        for process in self.tree():
            try:
                rss += process.memory_info().rss
                times = process.cpu_times()
                cpu += times.user + times.system
            except psutil.Error:
                pass
        if rss:
            self.rss = rss
            self.peak = max(self.peak, rss)
            self.cpu = max(self.cpu, cpu)

    def run(self):
        while not self.stopped.wait(self.interval):
            self.sample()

    def now(self) -> Usage:
        self.sample()
        return Usage(rss_mb=self.rss / MB, peak_rss_mb=self.peak / MB, cpu_s=self.cpu)

    def reset_peak(self):
        self.sample()
        self.peak = self.rss

    def stop(self):
        self.stopped.set()
        self.thread.join()


class Client(LanguageClient):
    """Answers what a server asks of its editor, and keeps count of the work it reports."""

    def __init__(self):
        super().__init__("cjls-perf", "0.1.0")
        self.open_progress: set[str | int] = set()
        self.last_progress = time.perf_counter()
        self.any_progress = False
        self.protocol_errors: list[str] = []

        @self.feature(types.WINDOW_WORK_DONE_PROGRESS_CREATE)
        def create_progress(params: types.WorkDoneProgressCreateParams):
            return None

        @self.feature(types.PROGRESS)
        def progress(params: types.ProgressParams):
            kind = params.value.get("kind") if isinstance(params.value, dict) else None
            if kind == "begin":
                self.open_progress.add(params.token)
            elif kind == "end":
                self.open_progress.discard(params.token)
            self.any_progress = True
            self.last_progress = time.perf_counter()

        @self.feature(types.CLIENT_REGISTER_CAPABILITY)
        def register(params: types.RegistrationParams):
            return None

        @self.feature(types.WORKSPACE_CONFIGURATION)
        def configuration(params: types.ConfigurationParams):
            return [None for _ in params.items]

        @self.feature(types.TEXT_DOCUMENT_PUBLISH_DIAGNOSTICS)
        def diagnostics(params: types.PublishDiagnosticsParams):
            pass

        @self.feature(types.WINDOW_LOG_MESSAGE)
        def log_message(params: types.LogMessageParams):
            pass

        @self.feature(types.WINDOW_SHOW_MESSAGE)
        def show_message(params: types.ShowMessageParams):
            pass

    def report_server_error(self, error: Exception, source):
        """A message the server got wrong (R4 sends `workDoneProgress/create` without an `id`):
        noted in the report rather than failing the run, since an editor lives with it too."""
        cause = error.__cause__ or error
        note = f"{type(cause).__name__}: {cause}".splitlines()[0]
        if note not in self.protocol_errors:
            self.protocol_errors.append(note)


class Session:
    """A server started on a workspace; `async with` shuts it down, or kills it, whatever happens."""

    def __init__(self, server: Server, workspace: Workspace, log: pathlib.Path, timeout: float = 300):
        self.server = server
        self.workspace = workspace
        self.log = log
        self.timeout = timeout
        self.client = Client()
        self.sampler: Sampler | None = None
        self.result: types.InitializeResult | None = None
        self.started = 0.0
        self.drain: asyncio.Task | None = None

    async def __aenter__(self) -> "Session":
        env = {**os.environ, **self.server.env}
        self.started = time.perf_counter()
        await self.client.start_io(*self.server.command, env=env, cwd=self.workspace.root)
        process = self.client._server
        self.sampler = Sampler(process.pid)
        # pygls pipes stderr and never reads it: a server logging much would block on a full pipe
        self.drain = asyncio.create_task(self.copy_stderr(process.stderr))
        return self

    async def copy_stderr(self, stream: asyncio.StreamReader):
        self.log.parent.mkdir(parents=True, exist_ok=True)
        with open(self.log, "ab") as file:
            while chunk := await stream.read(65536):
                file.write(chunk)

    async def __aexit__(self, *exc):
        process = self.client._server
        try:
            if process.returncode is None and self.result is not None:
                await asyncio.wait_for(self.client.shutdown_async(None), timeout=10)
                self.client.exit(None)
                await asyncio.wait_for(process.wait(), timeout=10)
        except (TimeoutError, RuntimeError, OSError):
            pass
        finally:
            await self.kill()
            if self.sampler:
                self.sampler.stop()
            await asyncio.wait_for(self.client.stop(), timeout=10)
            if self.drain:
                await self.drain

    async def kill(self):
        process = self.client._server
        if process.returncode is not None:
            return
        try:
            for child in psutil.Process(process.pid).children(recursive=True):
                child.kill()
        except psutil.Error:
            pass
        process.kill()
        await process.wait()

    # lifecycle

    async def initialize(self) -> types.InitializeResult:
        root = self.workspace.root
        params = types.InitializeParams(
            process_id=os.getpid(),
            root_uri=root.as_uri(),
            root_path=str(root),
            workspace_folders=[types.WorkspaceFolder(uri=root.as_uri(), name=root.name)],
            capabilities=CAPABILITIES,
            initialization_options=self.server.initialization_options,
        )
        self.result = await asyncio.wait_for(self.client.initialize_async(params), self.timeout)
        self.client.initialized(types.InitializedParams())
        return self.result

    async def ready(self) -> float:
        """Waits until the server counts as started, as `servers.toml` says it does, and returns
        when that was, in ms since the process was spawned: the wait for quiet itself not counted."""
        initialized = self.since_start_ms()
        if self.server.ready == "initialized":
            return initialized
        self.client.last_progress = time.perf_counter()
        settle = self.server.settle_ms / 1000
        deadline = time.perf_counter() + self.timeout
        while time.perf_counter() < deadline:
            quiet = time.perf_counter() - self.client.last_progress
            if not self.client.open_progress and quiet >= settle:
                if not self.client.any_progress:
                    return initialized
                return (self.client.last_progress - self.started) * 1000
            await asyncio.sleep(0.01)
        raise TimeoutError(f"{self.server.name} still busy after {self.timeout}s")

    def since_start_ms(self) -> float:
        return (time.perf_counter() - self.started) * 1000

    def usage(self) -> Usage:
        return self.sampler.now()

    # capabilities

    @property
    def encoding(self) -> str:
        encoding = self.result.capabilities.position_encoding if self.result else None
        return encoding or types.PositionEncodingKind.Utf16

    def supports(self, capability: str) -> bool:
        return bool(getattr(self.result.capabilities, capability, None))

    # documents

    def open(self, path: pathlib.Path, text: str) -> str:
        uri = path.as_uri()
        self.client.text_document_did_open(
            types.DidOpenTextDocumentParams(
                text_document=types.TextDocumentItem(uri=uri, language_id="Cangjie", version=1, text=text)
            )
        )
        return uri

    def insert(self, uri: str, version: int, line: int, character: int, text: str):
        position = types.Position(line=line, character=character)
        self.client.text_document_did_change(
            types.DidChangeTextDocumentParams(
                text_document=types.VersionedTextDocumentIdentifier(uri=uri, version=version),
                content_changes=[
                    types.TextDocumentContentChangePartial(
                        range=types.Range(start=position, end=position), text=text
                    )
                ],
            )
        )

    async def symbols(self, uri: str) -> list:
        result = await asyncio.wait_for(
            self.client.text_document_document_symbol_async(
                types.DocumentSymbolParams(text_document=types.TextDocumentIdentifier(uri=uri))
            ),
            self.timeout,
        )
        return result or []


def column(text: str, encoding: str) -> int:
    """The length of `text`, a line's prefix, in the units of the encoding agreed on."""
    if encoding == types.PositionEncodingKind.Utf8:
        return len(text.encode("utf-8"))
    if encoding == types.PositionEncodingKind.Utf32:
        return len(text)
    return len(text.encode("utf-16-le")) // 2
