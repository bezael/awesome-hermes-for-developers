#!/usr/bin/env python3
"""
check_endpoint.py - fast, mechanical first pass over a FastAPI router file.

Flags four syntactic patterns worth a human/agent look before doing the full
semantic review (see references/*.md in this skill):

  1. Route missing `response_model=` on the decorator.
  2. Route with no docstring and no `summary=`.
  3. Bare `except:` / `except Exception:` that has no `raise` in its body.
  4. Blocking calls (requests.*, time.sleep, urllib.request.urlopen) inside an
     `async def` route or dependency.

This is a static, best-effort AST pass - it has false positives and false
negatives by design (see SKILL.md "Pitfalls"). It does not import or execute
the target file, so it's safe to run against untrusted code.

Usage:
    python check_endpoint.py path/to/router.py [more_files.py ...]

Exit code is 0 if no findings, 1 if at least one finding was reported.
"""

from __future__ import annotations

import ast
import sys
from dataclasses import dataclass, field

ROUTE_METHODS = {"get", "post", "put", "patch", "delete", "websocket"}

# module.attr pairs known to block the event loop if awaited-not, i.e. called
# directly inside an `async def` without `await`.
BLOCKING_CALLS = {
    ("requests", "get"),
    ("requests", "post"),
    ("requests", "put"),
    ("requests", "patch"),
    ("requests", "delete"),
    ("requests", "request"),
    ("time", "sleep"),
}
# `urlopen` is checked separately below since it's commonly imported as a bare
# name (`from urllib.request import urlopen`) rather than accessed as an
# attribute of a module.


@dataclass
class Finding:
    line: int
    function: str
    message: str


@dataclass
class FileReport:
    path: str
    findings: list[Finding] = field(default_factory=list)


def _decorator_is_route(dec: ast.expr) -> bool:
    """True if `dec` looks like @app.get(...) / @router.post(...) / etc."""
    if not isinstance(dec, ast.Call):
        return False
    func = dec.func
    return isinstance(func, ast.Attribute) and func.attr in ROUTE_METHODS


def _decorator_kwarg(dec: ast.Call, name: str) -> ast.expr | None:
    for kw in dec.keywords:
        if kw.arg == name:
            return kw.value
    return None


def _has_bare_or_broad_except_without_raise(node: ast.AST) -> list[int]:
    lines: list[int] = []
    for sub in ast.walk(node):
        if isinstance(sub, ast.ExceptHandler):
            is_bare = sub.type is None
            is_broad = isinstance(sub.type, ast.Name) and sub.type.id == "Exception"
            if not (is_bare or is_broad):
                continue
            has_raise = any(isinstance(s, ast.Raise) for s in ast.walk(sub))
            if not has_raise:
                lines.append(sub.lineno)
    return lines


def _call_matches_blocking(call: ast.Call) -> str | None:
    func = call.func
    if isinstance(func, ast.Attribute) and isinstance(func.value, ast.Name):
        pair = (func.value.id, func.attr)
        if pair in BLOCKING_CALLS:
            return f"{func.value.id}.{func.attr}(...)"
    if isinstance(func, ast.Name) and func.id == "urlopen":
        return "urlopen(...)"
    return None


def _find_blocking_calls_in_async(node: ast.AsyncFunctionDef) -> list[tuple[int, str]]:
    # Node ids that are the direct target of an `await ...` expression - if
    # someone did `await requests.get(...)` (unusual, but possible with a
    # custom async-compatible wrapper of the same name), don't flag it.
    awaited_ids = {id(a.value) for a in ast.walk(node) if isinstance(a, ast.Await)}

    found: list[tuple[int, str]] = []
    for sub in ast.walk(node):
        if isinstance(sub, ast.Call) and id(sub) not in awaited_ids:
            label = _call_matches_blocking(sub)
            if label:
                found.append((sub.lineno, label))
    return found


def check_file(path: str) -> FileReport:
    report = FileReport(path=path)
    with open(path, "r", encoding="utf-8") as fh:
        source = fh.read()
    tree = ast.parse(source, filename=path)

    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        route_decorators = [d for d in node.decorator_list if _decorator_is_route(d)]
        if not route_decorators:
            continue
        dec = route_decorators[0]

        # 1. response_model
        if _decorator_kwarg(dec, "response_model") is None:
            report.findings.append(
                Finding(node.lineno, node.name, "missing response_model= on the route decorator")
            )

        # 2. summary / docstring
        has_docstring = ast.get_docstring(node) is not None
        has_summary = _decorator_kwarg(dec, "summary") is not None
        if not has_docstring and not has_summary:
            report.findings.append(
                Finding(node.lineno, node.name, "no docstring and no summary= - route is undocumented in /docs")
            )

        # 3. broad/bare except without raise
        for ln in _has_bare_or_broad_except_without_raise(node):
            report.findings.append(
                Finding(ln, node.name, "bare/broad except with no raise - may silently swallow errors")
            )

        # 4. blocking calls inside async def
        if isinstance(node, ast.AsyncFunctionDef):
            for ln, label in _find_blocking_calls_in_async(node):
                report.findings.append(
                    Finding(ln, node.name, f"blocking call {label} inside async def - blocks the event loop")
                )

    return report


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__)
        return 2

    any_findings = False
    for path in argv:
        report = check_file(path)
        if not report.findings:
            print(f"{path}: OK - no mechanical findings (still do the semantic review in SKILL.md)")
            continue
        any_findings = True
        print(f"{path}:")
        for f in sorted(report.findings, key=lambda x: x.line):
            print(f"  line {f.line} [{f.function}] {f.message}")

    return 1 if any_findings else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
