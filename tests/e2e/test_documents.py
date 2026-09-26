import urllib.parse

from lsprotocol import types
from pytest_lsp import LanguageClient

# the emoji is two UTF-16 units and four UTF-8 bytes
TEXT = "/* 😀 */ class A {\n    func f() {}\n}\n"


def open_document(client: LanguageClient, uri: str, text: str, version: int = 1):
    client.text_document_did_open(
        types.DidOpenTextDocumentParams(
            text_document=types.TextDocumentItem(uri=uri, language_id="Cangjie", version=version, text=text)
        )
    )


async def outline(client: LanguageClient, uri: str) -> list[types.DocumentSymbol] | None:
    return await client.text_document_document_symbol_async(
        types.DocumentSymbolParams(text_document=types.TextDocumentIdentifier(uri=uri))
    )


def names(symbols: list[types.DocumentSymbol]) -> list[str]:
    return [s.name + ("(" + ",".join(names(s.children)) + ")" if s.children else "") for s in symbols]


def vs_code_uri(path) -> str:
    """The URI VS Code sends for `path`: a Windows drive letter lowercase and its colon escaped."""
    uri = path.as_uri()
    if len(path.drive) == 2:
        drive = path.drive[0].lower() + "%3A"
        uri = "file:///" + drive + uri[len("file:///") + 2 :]
    return uri


async def test_an_open_document_has_its_outline_in_the_columns_agreed_on(client: LanguageClient):
    # arrange
    uri = "untitled:Untitled-1"
    open_document(client, uri, TEXT)

    # act
    symbols = await outline(client, uri)

    # assert: Neovim counts in UTF-8, where the emoji is two columns more; VS Code only in UTF-16
    assert names(symbols) == ["A(f)"]
    a = symbols[0]
    assert a.kind == types.SymbolKind.Class
    column = 17 if client.position_encoding == types.PositionEncodingKind.Utf8 else 15
    assert a.selection_range.start == types.Position(line=0, character=column)
    assert a.range.end.line == 2
    assert a.children[0].selection_range.start == types.Position(line=1, character=9)


async def test_columns_are_bytes_when_the_client_counts_in_utf8(server: LanguageClient):
    # arrange
    capabilities = types.ClientCapabilities(
        general=types.GeneralClientCapabilities(
            position_encodings=[types.PositionEncodingKind.Utf8, types.PositionEncodingKind.Utf16]
        )
    )
    result = await server.initialize_session(types.InitializeParams(capabilities=capabilities))
    open_document(server, "untitled:a", TEXT)

    # act
    symbols = await outline(server, "untitled:a")

    # assert
    assert result.capabilities.position_encoding == types.PositionEncodingKind.Utf8
    assert symbols[0].selection_range.start == types.Position(line=0, character=17)

    await server.shutdown_session()


async def test_incremental_changes_apply_in_order(client: LanguageClient):
    # arrange
    uri = "untitled:Untitled-1"
    open_document(client, uri, TEXT)

    # act: rename `f` to `g`, then add a class after `A` - the second range is in the text the
    # first one left
    client.text_document_did_change(
        types.DidChangeTextDocumentParams(
            text_document=types.VersionedTextDocumentIdentifier(uri=uri, version=2),
            content_changes=[
                types.TextDocumentContentChangePartial(
                    range=types.Range(start=types.Position(line=1, character=9), end=types.Position(line=1, character=10)),
                    text="g",
                ),
                types.TextDocumentContentChangePartial(
                    range=types.Range(start=types.Position(line=3, character=0), end=types.Position(line=3, character=0)),
                    text="class Б {}\n",
                ),
            ],
        )
    )
    symbols = await outline(client, uri)

    # assert
    assert names(symbols) == ["A(g)", "Б"]


async def test_a_closed_document_goes_back_to_what_the_disk_holds(client: LanguageClient, tmp_path):
    # arrange: the editor's buffer differs from the file, and the URI is spelled as VS Code
    # spells it, which on Windows is not how Python does
    path = tmp_path / "a.cj"
    path.write_text("class OnDisk {}\n", encoding="utf-8")
    uri = vs_code_uri(path)
    open_document(client, uri, "class InTheBuffer {}\n")
    assert names(await outline(client, uri)) == ["InTheBuffer"]

    # act
    client.text_document_did_close(
        types.DidCloseTextDocumentParams(text_document=types.TextDocumentIdentifier(uri=uri))
    )

    # assert: any spelling of the path finds it
    assert names(await outline(client, uri)) == ["OnDisk"]
    assert names(await outline(client, path.as_uri())) == ["OnDisk"]
    assert names(await outline(client, urllib.parse.unquote(uri))) == ["OnDisk"]


async def test_a_document_the_server_does_not_know_has_no_outline(client: LanguageClient):
    # act, assert
    assert await outline(client, "untitled:nothing") is None
