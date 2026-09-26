"""cjls-perf: speed and memory of Cangjie language servers.

    uv run --project tests/perf python -m cjls_perf list
    uv run --project tests/perf python -m cjls_perf run --server cjls --server lsp-server -o perf.json
    uv run --project tests/perf python -m cjls_perf compare before.json after.json
"""

import argparse
import asyncio
import datetime
import json
import logging
import os
import pathlib
import platform
import statistics
import subprocess
import sys
import tempfile
import traceback

from . import scenarios, servers, workspace
from .session import Session

SCHEMA = 1


def git(*args: str) -> str | None:
    try:
        return subprocess.run(
            ["git", *args], cwd=servers.REPO, capture_output=True, text=True, check=True
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def provenance() -> dict:
    toolchain = servers.REPO / ".cangjie-version"
    return {
        "commit": git("rev-parse", "HEAD"),
        "dirty": bool(git("status", "--porcelain")),
        "toolchain": toolchain.read_text().strip() if toolchain.exists() else None,
    }


def host() -> dict:
    return {
        "os": platform.system(),
        "release": platform.release(),
        "machine": platform.machine(),
        "processor": platform.processor(),
        "cpus": os.cpu_count(),
        "python": platform.python_version(),
    }


async def measure(server: servers.Server, space: workspace.Workspace, name: str, options, logs, repeat):
    run = scenarios.SCENARIOS[name]
    runs, info, notes = [], None, []
    for attempt in range(repeat):
        log = logs / f"{server.name}.{name}.{attempt}.stderr.log"
        try:
            async with Session(server, space, log) as session:
                try:
                    runs.append(await run(session, options))
                finally:
                    notes += [note for note in session.client.protocol_errors if note not in notes]
                if session.result and session.result.server_info:
                    info = {"name": session.result.server_info.name, "version": session.result.server_info.version}
        except scenarios.Skipped as skipped:
            return {"status": "skipped", "reason": str(skipped)}, info
        except Exception as error:
            traceback.print_exc()
            return {"status": "failed", "error": f"{type(error).__name__}: {error}", "log": str(log), "notes": notes}, info
        print(f"  {server.name} {name} #{attempt + 1}: {format_metrics(runs[-1])}", file=sys.stderr)
    median = {key: statistics.median(run[key] for run in runs) for key in runs[0]}
    result = {"status": "ok", "runs": runs, "median": median}
    if notes:
        result["notes"] = notes
    return result, info


async def warm_up(server: servers.Server, space: workspace.Workspace, logs: pathlib.Path):
    """One start thrown away: the first run of a binary pays for the OS reading and checking it."""
    try:
        async with Session(server, space, logs / f"{server.name}.warm-up.stderr.log") as session:
            await scenarios.start(session)
    except Exception:
        pass  # the scenarios will say what is wrong


def format_metrics(metrics: dict[str, float]) -> str:
    return ", ".join(f"{key}={value:.1f}" for key, value in metrics.items())


async def run(args) -> dict:
    chosen = args.scenario or list(scenarios.SCENARIOS)
    options = scenarios.Options(keystrokes=args.keystrokes)
    with tempfile.TemporaryDirectory(prefix="cjls-perf-") as scratch:
        if args.workspace:
            space = workspace.existing(args.workspace.resolve(), args.file)
        else:
            space = workspace.generate(pathlib.Path(scratch) / "bench", args.lines)
        report = {
            "schema": SCHEMA,
            "timestamp": datetime.datetime.now(datetime.UTC).isoformat(timespec="seconds"),
            "host": host(),
            "repo": provenance(),
            "workspace": {
                "generated": not args.workspace,
                "root": str(args.workspace) if args.workspace else None,
                "subject": space.subject.name,
                "subject_lines": space.subject_text.count("\n"),
                "subject_bytes": space.subject.stat().st_size,
            },
            "options": {"keystrokes": args.keystrokes, "repeat": args.repeat, "scenarios": chosen},
            "servers": {},
        }
        for name in args.server:
            try:
                server = servers.load(name)
            except servers.Unavailable as unavailable:
                print(f"{name}: unavailable ({unavailable})", file=sys.stderr)
                report["servers"][name] = {"status": "unavailable", "reason": str(unavailable)}
                continue
            entry = {"status": "ok", "command": server.command, "info": None, "scenarios": {}}
            await warm_up(server, space, args.logs)
            for scenario in chosen:
                result, info = await measure(server, space, scenario, options, args.logs, args.repeat)
                entry["info"] = entry["info"] or info
                entry["scenarios"][scenario] = result
                if result["status"] != "ok":
                    print(f"  {name} {scenario}: {result['status']} ({result.get('reason') or result.get('error')})", file=sys.stderr)
            report["servers"][name] = entry
    return report


def compare(paths: list[pathlib.Path]) -> str:
    """A Markdown table of the medians: a column per server of each report, a row per metric."""
    columns, values = [], {}
    for path in paths:
        report = json.loads(path.read_text())
        commit = (report["repo"].get("commit") or "")[:7]
        for server, entry in report["servers"].items():
            label = f"{server} ({path.stem}, {commit})" if len(paths) > 1 else server
            columns.append(label)
            if entry["status"] != "ok":
                values.setdefault(("—", "status"), {})[label] = entry["status"]
            for scenario, result in entry.get("scenarios", {}).items():
                for metric, value in result.get("median", {}).items():
                    values.setdefault((scenario, metric), {})[label] = value
                if result["status"] != "ok":
                    values.setdefault((scenario, "status"), {})[label] = result["status"]
    lines = ["| scenario | metric | " + " | ".join(columns) + " |", "|---|---|" + "---|" * len(columns)]
    for (scenario, metric), row in values.items():
        cells = [row.get(column) for column in columns]
        text = ["" if c is None else c if isinstance(c, str) else f"{c:.1f}" for c in cells]
        lines.append(f"| {scenario} | {metric} | " + " | ".join(text) + " |")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(prog="cjls_perf", description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(dest="command", required=True)

    commands.add_parser("list", help="the servers (and whether they run here) and the scenarios")

    run_parser = commands.add_parser("run", help="measure servers, write a JSON report")
    run_parser.add_argument("--server", action="append", required=True, help="a name from servers.toml; repeatable")
    run_parser.add_argument("--scenario", action="append", choices=list(scenarios.SCENARIOS), help="repeatable; all by default")
    run_parser.add_argument("--lines", type=int, default=5000, help="size of the generated subject file")
    run_parser.add_argument("--workspace", type=pathlib.Path, help="a cjpm project of one's own instead of a generated one")
    run_parser.add_argument("--file", type=pathlib.Path, help="the subject within --workspace; its largest .cj file by default")
    run_parser.add_argument("--keystrokes", type=int, default=50)
    run_parser.add_argument("--repeat", type=int, default=3, help="runs per scenario; the report keeps each and their median")
    run_parser.add_argument("--logs", type=pathlib.Path, default=pathlib.Path("perf-logs"), help="where the servers' stderr goes")
    run_parser.add_argument("-o", "--output", type=pathlib.Path, help="the JSON report; stdout by default")

    compare_parser = commands.add_parser("compare", help="a Markdown table of one or more reports")
    compare_parser.add_argument("reports", type=pathlib.Path, nargs="+")

    args = parser.parse_args()
    # pygls logs every message a server gets wrong, with its traceback; the report notes them instead
    logging.getLogger("pygls").setLevel(logging.CRITICAL)
    if args.command == "list":
        for name in servers.names():
            try:
                command = servers.load(name).command
                print(f"{name}: {' '.join(command)}")
            except servers.Unavailable as unavailable:
                print(f"{name}: unavailable ({unavailable})")
        print("scenarios: " + ", ".join(scenarios.SCENARIOS))
    elif args.command == "run":
        report = asyncio.run(run(args))
        text = json.dumps(report, indent=2)
        if args.output:
            args.output.write_text(text + "\n")
        else:
            print(text)
        failed = [
            f"{server}/{scenario}"
            for server, entry in report["servers"].items()
            for scenario, result in entry.get("scenarios", {}).items()
            if result["status"] == "failed"
        ]
        if failed:
            sys.exit(f"failed: {', '.join(failed)}")
    else:
        print(compare(args.reports))


if __name__ == "__main__":
    main()
