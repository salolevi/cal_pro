#!/usr/bin/env bash
#
# Rebuild a scratch Postgres database, apply the migration, and run the schema
# tests. Verifies the SQL locally without touching the Supabase project.
#
#   ./supabase/tests/run_local.sh
#
# Requires: brew install postgresql@16
#
# Note on LC_ALL: without a valid locale, Postgres on macOS fails at startup
# with "postmaster became multithreaded during startup".

set -euo pipefail

export PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH"
export LC_ALL="en_US.UTF-8"

PGDATA="/opt/homebrew/var/postgresql@16"
DB="calorar_test"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if ! pg_isready -q 2>/dev/null; then
  echo "==> starting postgres"
  pg_ctl -D "$PGDATA" -l /tmp/pg.log start
  sleep 3
fi

echo "==> rebuilding $DB"
dropdb --if-exists "$DB"
createdb "$DB"

echo "==> shim"
psql -d "$DB" -v ON_ERROR_STOP=1 -q -f "$ROOT/supabase/tests/00_supabase_shim.sql"

echo "==> migration"
for f in "$ROOT"/supabase/migrations/*.sql; do
  echo "    $(basename "$f")"
  psql -d "$DB" -v ON_ERROR_STOP=1 -q -f "$f"
done

echo "==> search tests"
psql -d "$DB" -v ON_ERROR_STOP=1 -f "$ROOT/supabase/tests/01_search_test.sql"

echo "==> rls tests"
# The last statement is expected to fail, so this file runs without
# ON_ERROR_STOP; read the output and confirm the RLS violation appears.
psql -d "$DB" -f "$ROOT/supabase/tests/02_rls_test.sql"

echo
echo "==> done. Expected final line: 'new row violates row-level security policy'"
