---
name: postgres-safe-query
description: >
  Query a production PostgreSQL database safely and read-only from Hermes.
  Enforces a dedicated read-only role, rejects any write/DDL/stacked-statement
  payload before it reaches the database, caps row counts and execution time,
  and never lets a connection string or password enter the agent's context or
  logs. Use whenever Hermes needs to answer a question against a live
  production Postgres database (debugging, support triage, reporting,
  ad-hoc analytics) without risking a write, a runaway scan that saturates
  the connection pool, or a leaked credential.
version: 0.1.0
platforms:
  - hermes
metadata:
  hermes:
    tags:
      - postgresql
      - database
      - security
      - read-only
      - sql
    category: database
---

# Postgres Safe Query

> **Estado:** skill original, escrita para este catálogo. Lo que sí se
> verificó de forma aislada: `scripts/validate_query.py` corrido a mano
> contra ~15 casos (los ejemplos de la sección Pitfalls, más queries
> normales), confirmando que rechaza lo que debe rechazar y deja pasar lo
> que debe pasar — esto no requiere una base de datos, es procesamiento de
> texto puro. Lo que **no** se verificó: el rol `hermes_readonly`, el
> wrapper `run-safe-query.sh` y la transacción `SET LOCAL` no se han
> ejecutado contra un PostgreSQL real, y la skill completa **todavía no se
> ha probado contra una instancia de Hermes real** conectada a una base de
> datos de producción. Trátala como punto de partida auditable, no como un
> binario probado en batalla — corre el checklist de la sección
> Verification antes de confiar en ella con datos reales.

## When to Use

Activate this skill when Hermes is asked to look something up in a
PostgreSQL database that is **not** disposable — staging with real-looking
data, or production. Typical triggers:

- "¿Cuántos usuarios se registraron ayer?" / "why does this customer's
  account show the wrong plan?"
- Debugging a support ticket by inspecting rows in the app's own database.
- Ad-hoc reporting/analytics questions that don't justify standing up a BI
  tool.
- Any request where the natural next step would be "let me just run a quick
  query" against a database that also serves live traffic.

**Do not use this skill for:**

- Schema migrations, seeding, or any statement that is expected to write.
  That's a different, higher-trust workflow with its own review step — this
  skill is read-only by design and will refuse writes on purpose.
- Databases you already treat as scratch/disposable (a local dev DB, a
  throwaway container). The overhead here (dedicated role, timeouts, row
  caps) exists specifically to protect data and uptime you can't casually
  restore.
- Introspecting schema structure as an end in itself — pair this skill with
  a dedicated introspection skill for that (see this category's README for a
  recommendation) instead of running `information_schema` queries ad hoc
  through this validator.

## Procedure

### 1. Connect through a role that cannot write, no matter what

Never reuse the application's owner/migration credentials. Provision (or ask
a human to provision) a dedicated role and use `templates/readonly-role.sql`
as the starting point:

```sql
CREATE ROLE hermes_readonly WITH LOGIN PASSWORD :'hermes_readonly_password';
GRANT CONNECT ON DATABASE app_production TO hermes_readonly;
GRANT USAGE ON SCHEMA public TO hermes_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO hermes_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO hermes_readonly;

-- Defense in depth: even if every check below has a bug, the role itself
-- cannot write or hold a transaction open forever.
ALTER ROLE hermes_readonly SET default_transaction_read_only = on;
ALTER ROLE hermes_readonly SET statement_timeout = '5s';
ALTER ROLE hermes_readonly SET idle_in_transaction_session_timeout = '10s';
```

This is the layer that actually protects you. Everything below is a second
layer — treat it as "fail fast and give a clear reason," not as the reason
you're safe.

### 2. Never let the agent see or print the connection string

Read the DSN from an environment variable or secrets manager at connection
time (`templates/.env.example` lists the expected variable names). Concrete
rules:

- The DSN is never a CLI argument (`ps aux` / shell history would leak it) —
  only ever an environment variable read directly by the connecting process.
- If a connection error surfaces, strip the DSN from the message before it
  reaches the agent's context or any log line. libpq errors sometimes echo
  the connection target — redact host/user, never the password specifically
  because the whole string should already be absent.
- Prefer `sslmode=verify-full` and a connection pooler (PgBouncer) in front
  of the database rather than the agent holding a long-lived direct
  connection.
- See `references/credential-handling.md` for the full checklist (rotation,
  pooler quirks, what to do if a secret does leak into a transcript).

### 3. Validate the query before it touches the database

Run every query through `scripts/validate_query.py` before execution. It is
a **first line of defense**, not a replacement for step 1 — read
`references/query-validation-rules.md` for why naive keyword-blocking is not
enough on its own (writable CTEs, stacked statements, comment-obfuscated
keywords). The validator:

1. Parses the statement count and rejects anything but exactly one
   statement (blocks `SELECT 1; DROP TABLE users;`-style stacking).
2. Strips comments and normalizes case, then rejects the statement if it
   contains `INSERT`, `UPDATE`, `DELETE`, `DROP`, `ALTER`, `TRUNCATE`,
   `GRANT`, `REVOKE`, `CREATE`, `COPY`, `CALL`, `DO`, `VACUUM`, `MERGE`, or
   `EXECUTE` **anywhere** in the statement — including inside a CTE, not
   just at the start.
3. Rejects known file/program-access functions even inside an otherwise
   read-only `SELECT` — `pg_read_file`, `pg_read_binary_file`, `pg_ls_dir`,
   `lo_import`, `lo_export`, and `COPY ... TO/FROM PROGRAM`.
4. Confirms the statement starts with `SELECT`, `WITH`, `EXPLAIN`, `TABLE`,
   or `VALUES` (the read-only entry points Postgres allows).
5. Enforces a row cap: if there is no `LIMIT`, it appends one
   (`DEFAULT_ROW_LIMIT`, 200 by default); if there is a `LIMIT` above the
   configured max (`MAX_ROW_LIMIT`, 5000 by default), it clamps it down.

```bash
python scripts/validate_query.py "SELECT * FROM orders WHERE status = 'failed'"
# -> SELECT * FROM orders WHERE status = 'failed' LIMIT 200
```

### 4. Execute inside a read-only transaction with a hard timeout

Even though the role already defaults to read-only with a statement timeout,
set both explicitly per-transaction with `SET LOCAL` (never bare `SET` — see
the PgBouncer pitfall below), then roll back regardless of outcome since
nothing here should ever need to commit:

```sql
BEGIN;
SET LOCAL statement_timeout = '5000ms';
SET LOCAL transaction_read_only = on;
-- run the validated query here
ROLLBACK;
```

`scripts/run-safe-query.sh` wraps this with `psql -v ON_ERROR_STOP=1` and
pipes the query through the validator first. Use it as the reference
implementation for wiring this into Hermes's tool-calling.

### 5. Report results, not raw dumps

Summarize row counts, truncation (`"showing the first 200 of >200 rows,
narrow the WHERE clause for more"`), and execution time back to the user.
If a query was clamped or rejected, say so explicitly instead of silently
returning a subset — the person asking needs to know the answer might be
incomplete.

## Pitfalls

- **`LIMIT` does not bound cost, only output rows.** A `LIMIT 200` on a
  query with no `WHERE` clause can still force a full sequential scan (or a
  disk-spilling sort) on a billion-row table before the limit is applied.
  The row cap is a usability feature; `statement_timeout` is the actual
  safety backstop. Never treat the row limit alone as a performance
  guarantee.
- **Writable CTEs look like `SELECT`s.** `WITH deleted AS (DELETE FROM
  sessions WHERE expired = true RETURNING *) SELECT count(*) FROM deleted;`
  starts with `WITH` and ends in a `SELECT`, but performs a delete. Keyword
  scanning must cover the entire statement body, not just the outermost
  clause — see `references/query-validation-rules.md`.
- **Stacked statements slip through naive `str.startswith("SELECT")`
  checks.** `SELECT 1; DROP TABLE users;` passes a prefix check. Always
  confirm the statement count first.
- **Comments and case can hide a keyword from a lazy regex.** `SEL/*x*/ECT`
  won't parse as `SELECT` anyway, but `dRoP TaBlE` or a keyword split across
  a `--` comment can defeat a case-sensitive or comment-unaware matcher.
  Normalize case and strip comments before matching.
- **A bare `SET statement_timeout = ...` can leak across sessions behind a
  pooler.** In PgBouncer's transaction pooling mode, a session-level `SET`
  can persist on the underlying server connection and silently affect the
  *next* client that picks it up, unless `server_reset_query` is configured
  correctly. Always use `SET LOCAL` inside an explicit transaction so the
  setting dies with `COMMIT`/`ROLLBACK`.
- **Fetching everything into memory before truncating client-side defeats
  the entire safety model.** If the row cap is applied after the full
  result set is materialized in the agent process, a huge table still gets
  fully scanned and fully transferred. Enforce the cap in the SQL (`LIMIT`)
  or via a cursor with a bounded `FETCH`, not after the fact.
- **`EXPLAIN ANALYZE` actually executes the query.** It's not a safe way to
  "just check the plan" for a query with expensive volatile functions or
  side-effecting calls — the query genuinely runs. Prefer plain `EXPLAIN`
  (no `ANALYZE`) when you only need estimated costs, and only add `ANALYZE`
  on the same footing as running the query for real.
- **Superuser or table-owner credentials bypass every check above.** If the
  role Hermes connects as can `INSERT`/`DROP`, every guard here is
  advisory — a prompt injection or a bug in the validator is the only thing
  standing between the model and a write. The role from step 1 is the real
  control; the validator is a courtesy layer that fails fast with a
  legible error instead of relying on the database to reject a write it was
  never permissioned to make.

## Verification

Run these checks after wiring this skill into a real Hermes instance, before
trusting it against production:

1. **Confirm the role can't write.**
   ```sql
   SELECT current_user, session_user,
          (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) AS is_superuser;
   ```
   `is_superuser` must be `false`. Then attempt a throwaway write
   (`INSERT INTO a_scratch_table ...`) through the *same* credentials outside
   this skill and confirm Postgres itself rejects it — the role must be
   safe even with the validator removed.

2. **Confirm the validator rejects the known bypass shapes.** Feed
   `scripts/validate_query.py` each pitfall example above (stacked
   statement, writable CTE, `COPY ... TO PROGRAM`, comment-obfuscated
   keyword) and confirm every one is rejected with a clear reason, not
   silently passed through.

3. **Confirm the row cap is enforced server-side.** Run a query with no
   `LIMIT` against a table with more rows than `MAX_ROW_LIMIT` and confirm
   exactly the capped number of rows comes back — and that the response
   tells the user the result was truncated.

4. **Confirm the timeout actually cancels.** Run `SELECT pg_sleep(30);`
   through the full pipeline with `statement_timeout` set to `5s` and
   confirm Postgres cancels it (`ERROR: canceling statement due to
   statement timeout`) rather than the client hanging or the agent waiting
   30 seconds.

5. **Confirm nothing sensitive reached the transcript.** Grep whatever logs
   or transcripts the run produced for the password and full DSN. Neither
   should appear anywhere, including in error paths.

*Ninguno de estos cinco pasos se ha corrido todavía contra un Hermes real —
son el checklist que hay que ejecutar antes de confiar esta skill con datos
de producción de verdad.*
