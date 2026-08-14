-- Minimal stand-ins for what Supabase provides out of the box, so the real
-- migration can be executed unmodified against a vanilla Postgres instance.
--
-- Idempotent: roles are cluster-wide and survive dropdb, so guard their
-- creation rather than failing on re-run.

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role;
  end if;
end
$$;

create schema if not exists auth;

create table if not exists auth.users (
  id    uuid primary key default gen_random_uuid(),
  email text unique
);

-- In Supabase this reads the JWT claim; here it just needs to exist with the
-- right signature so the RLS policies compile.
create or replace function auth.uid()
returns uuid
language sql
stable
as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
