"""Semantic tokens as an editor asks for them: what the unit tests cannot see is the request and its answer over stdio,
with a real client's capabilities. What each token is, is a unit test (C7)."""

from lsprotocol import types
from pytest_lsp import LanguageClient
from test_documents import open_document


async def test_a_document_is_highlighted_from_its_start(client: LanguageClient):
    # arrange
    uri = "untitled:a"
    open_document(client, uri, "class A {}\nlet b = 1")

    # act
    tokens = await client.text_document_semantic_tokens_full_async(
        types.SemanticTokensParams(text_document=types.TextDocumentIdentifier(uri=uri))
    )

    # assert: five numbers a token; `class` first, a keyword, the legend's first type
    assert tokens is not None
    assert len(tokens.data) % 5 == 0
    assert list(tokens.data[:5]) == [0, 0, 5, 0, 0]
    # `let` starts the next line
    assert [tokens.data[i] for i in range(0, len(tokens.data), 5)].count(1) == 1
