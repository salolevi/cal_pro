-- RLS isolation checks. Run after 00_supabase_shim.sql, the migration, and
-- 01_search_test.sql (this file reuses the products that one seeds).
--
-- Expected: Ana sees exactly one diary entry and one profile, the catalog stays
-- readable, and the final INSERT fails with
--   "new row violates row-level security policy".
-- A failure reading "permission denied for table ..." means the GRANTs are
-- missing, which is a different bug from an RLS misconfiguration.

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'ana@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'beto@example.com');

insert into public.profiles (id, display_name) values
  ('11111111-1111-1111-1111-111111111111', 'Ana'),
  ('22222222-2222-2222-2222-222222222222', 'Beto');

insert into public.diary_entries (user_id, logged_at, product_id, quantity)
select '11111111-1111-1111-1111-111111111111', now() - interval '4 hours', id, 200
from public.products where name like 'Leche%';

insert into public.diary_entries (user_id, logged_at, product_id, quantity)
select '22222222-2222-2222-2222-222222222222', now() - interval '1 hour', id, 355
from public.products where name like 'Cerveza%';

\echo ''
\echo '=== superuser sees both entries (RLS bypassed) — expect 2 ==='
select count(*) as total from public.diary_entries;

set role authenticated;
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

\echo ''
\echo '=== as Ana: own diary entries only — expect 1 row ==='
select to_char(logged_at, 'HH24:MI') as hora, quantity from public.diary_entries;

\echo ''
\echo '=== as Ana: own profile only — expect 1 (Ana) ==='
select display_name from public.profiles;

\echo ''
\echo '=== as Ana: catalog readable — expect 5 ==='
select count(*) as products_visible from public.products;

\echo ''
\echo '=== as Ana: search callable — expect 2 Serenísima rows ==='
select name from public.search_products('serenisima');

\echo ''
\echo '=== as Ana: writing a row owned by Beto MUST fail ==='
insert into public.diary_entries (user_id, logged_at, product_id, quantity)
select '22222222-2222-2222-2222-222222222222', now(), id, 100
from public.products limit 1;
