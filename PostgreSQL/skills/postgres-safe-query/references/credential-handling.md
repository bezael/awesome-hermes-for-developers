# Credential handling checklist

Rules for how Hermes obtains and handles the database connection for this
skill. The goal is that a full connection string or password never has a
reason to pass through the model's context window, a tool-call log, or a
transcript — not "we redact it if we notice it," but "it structurally
cannot get there."

## Where the credential comes from

- Read the DSN from an environment variable (see `templates/.env.example`
  for the expected names) or from whatever secrets manager Hermes already
  integrates with. The connecting script/tool reads it directly at connect
  time — the value never becomes a function argument that an LLM tool call
  constructs, passes, or echoes back.
- Never accept the DSN, host, user, or password as a parameter the model
  fills in. If the model can write the value into a tool call, it can also
  paraphrase, log, or "helpfully" repeat it back in a response.
- Never pass the DSN as a CLI argument to `psql` or any script. Arguments
  are visible to any other process on the box via `ps aux` / `/proc/<pid>/cmdline`,
  and they land in shell history. Use `PGPASSWORD`/`PGSERVICE`/a `.pgpass`
  file or a connection URI read from an environment variable that the
  process reads internally, not one interpolated into the invoked command
  line.

## Transport

- `sslmode=require` is the floor; prefer `sslmode=verify-full` with a
  trusted CA so the connection can't be silently downgraded or
  man-in-the-middled onto a different host.
- Put a connection pooler (PgBouncer, or your cloud provider's managed
  pooler) in front of the database rather than letting Hermes hold direct,
  long-lived connections. This also gives you a single place to look at
  active sessions and kill one if something misbehaves.

## Error handling

- If a connection attempt fails, the error that reaches the agent's context
  must not include the DSN. Many drivers' error messages include the target
  host/port/user by default (e.g. "could not connect to server: ... user
  hermes_readonly, database app_production"). Catch the exception at the
  boundary and re-raise a sanitized message ("could not connect to the
  database — check with an operator") rather than letting the raw driver
  exception bubble up into a transcript.
- Never log the full connection string "just for debugging." If you need to
  confirm which database a query hit, log the database name and role, not
  the password or full URI.

## Rotation and scope

- Rotate the `hermes_readonly` credential on the same cadence as any other
  service credential — it is not exempt just because it's read-only. A
  leaked read-only credential is still a full read of everything that role
  can see.
- Scope the role to the schema(s) it actually needs (`GRANT SELECT ON ALL
  TABLES IN SCHEMA public`, not the whole database) — see
  `templates/readonly-role.sql`. If the database has a schema with PII that
  this skill's use case doesn't need, don't grant `SELECT` on it in the
  first place; that's a stronger guarantee than trusting the query
  validator to never be asked about it.
- If the database is multi-tenant, pair this role with row-level security
  policies scoped to whatever tenant context Hermes is allowed to see,
  rather than relying on every query happening to include the right `WHERE`
  clause.

## If a credential does leak into a transcript

- Rotate it immediately — treat it the same as any other leaked secret,
  regardless of the fact that the role is read-only.
- Check `pg_stat_activity` / your pooler's connection log for any activity
  from that role you can't account for, in the window between the leak and
  the rotation.
- Fix the specific code path that let it leak before re-enabling the skill
  — don't just rotate and move on, since the same path will leak the new
  credential too.
