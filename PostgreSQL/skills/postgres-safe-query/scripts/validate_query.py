#!/usr/bin/env python3
"""
validate_query.py — first-line-of-defense validator for postgres-safe-query.

Pure standard library, no third-party SQL parser. This is deliberately a
heuristic (comment/string masking + keyword and paren-depth scanning), not a
full SQL parser. It exists to fail fast with a clear reason on the known
bypass shapes documented in ../references/query-validation-rules.md. It is
NOT a substitute for connecting through a role that cannot write — see
../SKILL.md step 1. If this script has a bug, the database role is what
actually keeps you safe.

Usage:
    python validate_query.py "SELECT * FROM orders WHERE status = 'failed'"
    echo "SELECT 1;" | python validate_query.py

Exit code 0 and the (possibly rewritten, LIMIT-enforced) query on stdout if
the query passes. Exit code 1 and a reason on stderr if it is rejected.
"""

from __future__ import annotations

import re
import sys

DEFAULT_ROW_LIMIT = 200
MAX_ROW_LIMIT = 5000

# Anywhere these appear as a standalone keyword, the statement is rejected —
# regardless of whether they're the leading clause (catches writable CTEs).
BLOCKLIST_KEYWORDS = [
    "INSERT", "UPDATE", "DELETE", "MERGE", "DROP", "ALTER", "TRUNCATE",
    "GRANT", "REVOKE", "CREATE", "COPY", "CALL", "VACUUM", "EXECUTE",
    "REINDEX", "CLUSTER", "REFRESH", "LISTEN", "NOTIFY",
]

# "DO" is a keyword (anonymous code block) but also a common English word in
# comments/strings that get masked out already, so a word-boundary match is
# safe here too.
BLOCKLIST_KEYWORDS.append("DO")

# Functions that read/write the filesystem or invoke server-side programs.
# Reject if the name appears immediately followed by "(" (a call), anywhere
# in the statement.
BLOCKLIST_FUNCTIONS = [
    "pg_read_file", "pg_read_binary_file", "pg_ls_dir", "pg_ls_logdir",
    "pg_ls_waldir", "lo_import", "lo_export", "dblink_exec",
    "pg_terminate_backend", "pg_cancel_backend",
]

# COPY is already in BLOCKLIST_KEYWORDS, but "TO PROGRAM" / "FROM PROGRAM" is
# called out explicitly in case COPY is ever removed from the keyword list
# for a legitimate reason (e.g. a future read-only COPY ... TO STDOUT
# allowance) — don't let that accidentally re-open the PROGRAM bypass.
PROGRAM_PATTERN = re.compile(r"\bPROGRAM\b", re.IGNORECASE)

# A statement must start with one of these to be considered read-only.
# Independent of the blocklist: failing to match this is its own rejection
# reason, so new/unanticipated syntax fails closed.
ALLOWLIST_PREFIXES = ("SELECT", "WITH", "EXPLAIN", "TABLE", "VALUES")

_DOLLAR_TAG_RE = re.compile(r"\$([A-Za-z_][A-Za-z0-9_]*)?\$")


class RejectedQuery(Exception):
    pass


def _mask(sql: str) -> str:
    """Return a same-length copy of sql with comment bodies and string /
    quoted-identifier / dollar-quoted contents replaced by 'x'. Used only
    for keyword and structural analysis — never returned to the caller.
    Preserving length lets callers map a match position in the masked text
    back to the same offset in the original text.
    """
    out = []
    i, n = 0, len(sql)
    while i < n:
        c = sql[i]

        if c == "-" and sql[i + 1 : i + 2] == "-":
            j = sql.find("\n", i)
            j = n if j == -1 else j
            out.append(" " * (j - i))
            i = j
            continue

        if c == "/" and sql[i + 1 : i + 2] == "*":
            j = sql.find("*/", i + 2)
            j = n if j == -1 else j + 2
            out.append(" " * (j - i))
            i = j
            continue

        if c == "'":
            j = i + 1
            while j < n:
                if sql[j] == "'":
                    if sql[j + 1 : j + 2] == "'":
                        j += 2
                        continue
                    j += 1
                    break
                j += 1
            else:
                j = n
            out.append(sql[i] + "x" * max(0, j - i - 2) + sql[j - 1 if j <= n else i])
            i = j
            continue

        if c == '"':
            j = i + 1
            while j < n:
                if sql[j] == '"':
                    if sql[j + 1 : j + 2] == '"':
                        j += 2
                        continue
                    j += 1
                    break
                j += 1
            else:
                j = n
            out.append(sql[i] + "x" * max(0, j - i - 2) + sql[j - 1 if j <= n else i])
            i = j
            continue

        if c == "$":
            m = _DOLLAR_TAG_RE.match(sql, i)
            if m:
                tag = m.group(0)
                start_body = i + len(tag)
                j = sql.find(tag, start_body)
                if j == -1:
                    out.append("x" * (n - i))
                    i = n
                    continue
                out.append(tag + "x" * (j - start_body) + tag)
                i = j + len(tag)
                continue

        out.append(c)
        i += 1

    return "".join(out)


def _split_statements(masked: str) -> list[str]:
    """Split on real (unmasked) semicolons. Returns non-empty trimmed
    segments only."""
    return [seg.strip() for seg in masked.split(";") if seg.strip()]


def _paren_depth_at(masked: str, pos: int) -> int:
    depth = 0
    for ch in masked[:pos]:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
    return depth


def _keyword_re(word: str) -> re.Pattern:
    return re.compile(rf"(?<![A-Za-z0-9_]){re.escape(word)}(?![A-Za-z0-9_])", re.IGNORECASE)


def validate(raw_query: str, default_limit: int = DEFAULT_ROW_LIMIT,
             max_limit: int = MAX_ROW_LIMIT) -> str:
    """Return a safe, LIMIT-enforced query, or raise RejectedQuery."""
    original = raw_query.strip()
    if not original:
        raise RejectedQuery("empty query")

    masked_full = _mask(original)

    statements = _split_statements(masked_full)
    if len(statements) == 0:
        raise RejectedQuery("empty query")
    if len(statements) > 1:
        raise RejectedQuery(
            f"multiple statements detected ({len(statements)}) - only a single "
            "read-only statement is allowed"
        )

    # Re-derive the single statement's original text (strip a trailing ';').
    stmt_original = original.rstrip().rstrip(";").strip()
    stmt_masked = masked_full.rstrip().rstrip(";").strip()
    # Re-align: find where stmt_masked begins in masked_full to slice
    # stmt_original from the same offset (masking is length-preserving).
    start = masked_full.find(stmt_masked) if stmt_masked else 0
    stmt_original = original[start : start + len(stmt_masked)] if stmt_masked else ""

    if not stmt_masked:
        raise RejectedQuery("empty query")

    if not stmt_masked.upper().startswith(ALLOWLIST_PREFIXES):
        raise RejectedQuery(
            "statement does not start with an allowed read-only clause "
            f"({', '.join(ALLOWLIST_PREFIXES)})"
        )

    for kw in BLOCKLIST_KEYWORDS:
        m = _keyword_re(kw).search(stmt_masked)
        if m:
            raise RejectedQuery(f"blocked keyword '{kw}' found in statement")

    for fn in BLOCKLIST_FUNCTIONS:
        if re.search(rf"(?<![A-Za-z0-9_]){re.escape(fn)}\s*\(", stmt_masked, re.IGNORECASE):
            raise RejectedQuery(f"blocked function '{fn}(...)' found in statement")

    if PROGRAM_PATTERN.search(stmt_masked):
        raise RejectedQuery("'PROGRAM' found in statement (COPY ... TO/FROM PROGRAM is blocked)")

    return _enforce_row_limit(stmt_original, stmt_masked, default_limit, max_limit)


def _enforce_row_limit(stmt_original: str, stmt_masked: str,
                        default_limit: int, max_limit: int) -> str:
    limit_re = re.compile(r"\bLIMIT\b\s+(\d+)", re.IGNORECASE)

    top_level_match = None
    for m in limit_re.finditer(stmt_masked):
        if _paren_depth_at(stmt_masked, m.start()) == 0:
            top_level_match = m  # keep the last top-level LIMIT

    if top_level_match is None:
        return f"{stmt_original} LIMIT {default_limit}"

    existing_value = int(top_level_match.group(1))
    if existing_value <= max_limit:
        return stmt_original

    start, end = top_level_match.span(1)
    return stmt_original[:start] + str(max_limit) + stmt_original[end:]


def main() -> int:
    if len(sys.argv) > 1:
        raw_query = " ".join(sys.argv[1:])
    else:
        raw_query = sys.stdin.read()

    try:
        safe_query = validate(raw_query)
    except RejectedQuery as exc:
        print(f"REJECTED: {exc}", file=sys.stderr)
        return 1

    print(safe_query)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
