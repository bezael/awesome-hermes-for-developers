-- Dedicated read-only role for Hermes to connect through.
-- Run this as a superuser or the database owner, once, before wiring up
-- the postgres-safe-query skill. Replace app_production / public with your
-- actual database and schema name(s).
--
-- Usage:
--   psql "$ADMIN_DSN" -v hermes_readonly_password='...' -f readonly-role.sql

\set ON_ERROR_STOP on

-- 1. The role itself. LOGIN so it can connect; nothing else granted here —
--    every capability below is added explicitly, on purpose.
CREATE ROLE hermes_readonly WITH
  LOGIN
  PASSWORD :'hermes_readonly_password'
  NOSUPERUSER
  NOCREATEDB
  NOCREATEROLE
  NOREPLICATION
  CONNECTION LIMIT 5;

-- 2. Scope: connect to the one database, use the one schema this skill
--    actually needs. Do not GRANT ALL PRIVILEGES ON DATABASE — that
--    includes far more than SELECT.
GRANT CONNECT ON DATABASE app_production TO hermes_readonly;
GRANT USAGE ON SCHEMA public TO hermes_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO hermes_readonly;

-- 3. Cover tables created after this script runs, so you don't have to
--    remember to re-grant on every migration.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT ON TABLES TO hermes_readonly;

-- 4. Defense in depth at the role level — these apply even if the app or
--    the query validator has a bug. This is the layer that actually
--    protects the database; treat everything the skill does in the
--    application layer as a second, advisory layer on top of this.
ALTER ROLE hermes_readonly SET default_transaction_read_only = on;
ALTER ROLE hermes_readonly SET statement_timeout = '5s';
ALTER ROLE hermes_readonly SET idle_in_transaction_session_timeout = '10s';

-- 5. Explicitly revoke the ability to read/write server-side files or
--    invoke server-side programs. These are usually already restricted to
--    superuser / pg_read_server_files / pg_execute_server_program in
--    modern Postgres, but make the intent explicit rather than relying on
--    defaults you didn't set yourself.
REVOKE EXECUTE ON FUNCTION pg_read_file(text) FROM hermes_readonly;
REVOKE EXECUTE ON FUNCTION pg_ls_dir(text) FROM hermes_readonly;

-- 6. If the database is multi-tenant, add row-level security policies
--    here scoped to whatever tenant context this skill is allowed to see.
--    There is no generic policy that fits every schema — write one
--    specific to yours, and enable it with:
--      ALTER TABLE <table> ENABLE ROW LEVEL SECURITY;
--      CREATE POLICY <name> ON <table> FOR SELECT TO hermes_readonly
--        USING (<tenant scoping condition>);

-- Verification (run as hermes_readonly after connecting):
--   SELECT current_user, session_user,
--          (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) AS is_superuser;
--   -- is_superuser must be false.
--   SHOW statement_timeout;          -- must be 5s
--   SHOW default_transaction_read_only; -- must be on
