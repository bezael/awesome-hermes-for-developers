#!/usr/bin/env bash
# run-safe-query.sh — reference wiring for postgres-safe-query.
#
# Validates the query (scripts/validate_query.py), then runs it against
# Postgres inside an explicit read-only transaction with a hard statement
# timeout, and always rolls back — nothing this skill runs should ever need
# to commit.
#
# Required environment variables (see ../templates/.env.example):
#   POSTGRES_READONLY_URL   connection URI for the hermes_readonly role
#   PG_STATEMENT_TIMEOUT_MS statement timeout in ms (default: 5000)
#
# Usage:
#   POSTGRES_READONLY_URL=... ./run-safe-query.sh "SELECT * FROM orders WHERE status = 'failed'"
#
# The query is NEVER taken from a second positional argument that gets
# embedded into a larger shell command elsewhere — pass it as the sole
# argument to this script, which hands it to psql via -v, not via shell
# string interpolation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATEMENT_TIMEOUT_MS="${PG_STATEMENT_TIMEOUT_MS:-5000}"

if [[ -z "${POSTGRES_READONLY_URL:-}" ]]; then
  echo "ERROR: POSTGRES_READONLY_URL is not set. Refusing to guess a connection target." >&2
  exit 1
fi

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 \"<single SQL query>\"" >&2
  exit 1
fi

RAW_QUERY="$1"

# 1. Validate and rewrite (LIMIT enforcement) before this query ever reaches
#    psql. If this rejects, stop here — do not fall back to running the raw
#    query "just this once."
if ! SAFE_QUERY="$(python3 "$SCRIPT_DIR/validate_query.py" "$RAW_QUERY")"; then
  echo "Query rejected by validator, not executed." >&2
  exit 1
fi

# 2. Execute inside an explicit read-only transaction with SET LOCAL (not a
#    bare SET) so the timeout/read-only setting cannot leak to another
#    session on a pooled connection (see SKILL.md pitfalls). ON_ERROR_STOP
#    ensures a mid-transaction error aborts instead of continuing past it.
#    The connection string itself only ever comes from the environment
#    variable psql reads directly — never pass it as a CLI argument.
psql "$POSTGRES_READONLY_URL" \
  -v ON_ERROR_STOP=1 \
  -v ON_ERROR_ROLLBACK=off \
  -c "BEGIN;" \
  -c "SET LOCAL statement_timeout = '${STATEMENT_TIMEOUT_MS}ms';" \
  -c "SET LOCAL transaction_read_only = on;" \
  -c "$SAFE_QUERY" \
  -c "ROLLBACK;"
