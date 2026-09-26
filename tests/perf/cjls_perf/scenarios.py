"""What is measured: each scenario starts a server of its own and returns its metrics.

A metric's name carries its unit (`_ms`, `_mb`, `_s`); a count has none. A scenario that needs a
capability the server does not advertise is skipped, not failed: the servers do not all do the
same things, and a missing feature is prior-art.md's business, not a number here.
"""

import statistics
import time
from collections.abc import Awaitable, Callable
from dataclasses import dataclass

from .session import Session, column


class Skipped(Exception):
    pass


@dataclass
class Options:
    keystrokes: int = 50


Scenario = Callable[[Session, Options], Awaitable[dict[str, float]]]
SCENARIOS: dict[str, Scenario] = {}


def scenario(name: str):
    def register(function: Scenario) -> Scenario:
        SCENARIOS[name] = function
        return function

    return register


def percentile(values: list[float], p: float) -> float:
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, round(p / 100 * (len(ordered) - 1)))]


def count(symbols: list) -> int:
    return sum(1 + count(getattr(s, "children", None) or []) for s in symbols)


async def start(session: Session) -> dict[str, float]:
    await session.initialize()
    initialized = session.since_start_ms()
    return {"initialize_ms": initialized, "ready_ms": await session.ready()}


@scenario("startup")
async def startup(session: Session, options: Options) -> dict[str, float]:
    """From the process spawned to its `initialize` answer, then to ready; what it costs to sit there."""
    metrics = await start(session)
    usage = session.usage()
    return {**metrics, "rss_ready_mb": usage.rss_mb, "peak_rss_mb": usage.peak_rss_mb, "cpu_s": usage.cpu_s}


@scenario("open")
async def open_document(session: Session, options: Options) -> dict[str, float]:
    """The subject opened, until its first outline: the first read of a file, a cold one."""
    await start(session)
    if not session.supports("document_symbol_provider"):
        raise Skipped("no documentSymbolProvider")
    before = session.usage()
    session.sampler.reset_peak()

    text = session.workspace.subject_text
    began = time.perf_counter()
    uri = session.open(session.workspace.subject, text)
    symbols = await session.symbols(uri)
    elapsed = (time.perf_counter() - began) * 1000

    after = session.usage()
    return {
        "open_to_symbols_ms": elapsed,
        "symbols": count(symbols),
        "rss_mb": after.rss_mb,
        "rss_growth_mb": after.rss_mb - before.rss_mb,
        "peak_rss_mb": after.peak_rss_mb,
        "cpu_s": after.cpu_s - before.cpu_s,
    }


@scenario("typing")
async def typing(session: Session, options: Options) -> dict[str, float]:
    """A declaration typed at the end of the subject, a character at a time, the outline asked for
    after each: the latency an editor refreshing its outline sees, and the memory edits leave."""
    await start(session)
    if not session.supports("document_symbol_provider"):
        raise Skipped("no documentSymbolProvider")
    text = session.workspace.subject_text
    uri = session.open(session.workspace.subject, text)
    await session.symbols(uri)
    before = session.usage()
    session.sampler.reset_peak()

    # the end of the file, in the columns agreed on; what is typed is ASCII, so it moves by one
    lines = text.split("\n")
    line, character = len(lines) - 1, column(lines[-1], session.encoding)
    typed = "\nfunc typed(x: Int64): Int64 {\n    x + 1\n}\n"
    latencies = []
    version = 1
    for i in range(options.keystrokes):
        char = typed[i % len(typed)]
        version += 1
        began = time.perf_counter()
        session.insert(uri, version, line, character, char)
        await session.symbols(uri)
        latencies.append((time.perf_counter() - began) * 1000)
        line, character = (line + 1, 0) if char == "\n" else (line, character + 1)

    after = session.usage()
    return {
        "keystroke_p50_ms": statistics.median(latencies),
        "keystroke_p95_ms": percentile(latencies, 95),
        "keystroke_max_ms": max(latencies),
        "rss_mb": after.rss_mb,
        "rss_growth_mb": after.rss_mb - before.rss_mb,
        "peak_rss_mb": after.peak_rss_mb,
        "cpu_s": after.cpu_s - before.cpu_s,
    }
