"""The servers the driver can run, as `servers.toml` describes them."""

import os
import pathlib
import re
import sys
import tomllib
from dataclasses import dataclass, field
from typing import Any

REPO = pathlib.Path(__file__).resolve().parents[3]
SERVERS = pathlib.Path(__file__).resolve().parents[1] / "servers.toml"

PLACEHOLDER = re.compile(r"\{(repo|env:([A-Za-z_][A-Za-z0-9_]*))\}")


class Unavailable(Exception):
    """The server cannot be run here: a variable it names is unset, or its binary is missing."""


@dataclass
class Server:
    name: str
    command: list[str]
    env: dict[str, str] = field(default_factory=dict)
    initialization_options: Any = None
    ready: str = "initialized"
    settle_ms: int = 500
    workspace: str = "files"


def expand(text: str) -> str:
    def substitute(match: re.Match) -> str:
        if match.group(1) == "repo":
            return str(REPO)
        value = os.environ.get(match.group(2))
        if not value:
            raise Unavailable(f"{match.group(2)} is not set")
        return value

    return PLACEHOLDER.sub(substitute, text)


def executable(path: str) -> str:
    candidates = [path, path + ".exe"] if sys.platform == "win32" else [path]
    for candidate in candidates:
        if pathlib.Path(candidate).is_file():
            return candidate
    raise Unavailable(f"{path} does not exist")


def resolve(argv: list[str]) -> list[str]:
    expanded = [expand(arg) for arg in argv]
    return [executable(expanded[0]), *expanded[1:]]


def load(name: str, path: pathlib.Path = SERVERS) -> Server:
    """The server named `name`, its command resolved; `Unavailable` when it cannot run here."""
    with open(path, "rb") as file:
        table = tomllib.load(file)
    if name not in table:
        raise KeyError(f"no server {name!r} in {path}; known: {', '.join(table)}")
    spec = table[name]
    try:
        command = resolve(spec["command"])
    except Unavailable:
        if "fallback-command" not in spec:
            raise
        command = resolve(spec["fallback-command"])
    return Server(
        name=name,
        command=command,
        env={key: expand(value) for key, value in spec.get("env", {}).items()},
        initialization_options=spec.get("initialization-options"),
        ready=spec.get("ready", "initialized"),
        settle_ms=spec.get("settle-ms", 500),
        workspace=spec.get("workspace", "files"),
    )


def names(path: pathlib.Path = SERVERS) -> list[str]:
    with open(path, "rb") as file:
        return list(tomllib.load(file))
