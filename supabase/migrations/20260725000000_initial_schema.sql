-- CalorAR — initial schema
--
-- Design notes:
--   * All nutrition is stored per 100 g/ml (canonical). Per-serving values are
--     derived at query time from products.serving_size. Storing one basis
--     removes a whole class of unit bugs.
--   * Search is the core differentiator, so it gets real attention here:
--     Spanish stemming + accent-insensitivity + trigram fuzzy matching.
--   * Catalog tables are world-readable; user tables are locked to their owner
--     via RLS.

-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------

create extension if not exists unaccent;   -- "serenisima" should match "Serenísima"
create extension if not exists pg_trgm;    -- typo tolerance: "yogurt" ~ "yoghurt"

-- unaccent() is STABLE, not IMMUTABLE, so it cannot be used in a generated
-- column or expression index directly. Pinning the dictionary explicitly makes
-- it safe to mark immutable. (Standard workaround; valid as long as the
-- 'unaccent' dictionary is not redefined.)
create or replace function public.immutable_unaccent(text)
returns text
language sql
immutable
parallel safe
strict
as $$ select public.unaccent('public.unaccent', $1) $$;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

-- Used for the Mifflin–St Jeor BMR equation, which is parameterised on sex.
create type public.sex as enum ('femenino', 'masculino');

create type public.activity_level as enum (
  'sedentario',    -- desk job, little exercise          x1.2
  'ligero',        -- light exercise 1-3 days/week       x1.375
  'moderado',      -- moderate exercise 3-5 days/week    x1.55
  'activo',        -- hard exercise 6-7 days/week        x1.725
  'muy_activo'     -- physical job or 2x/day training    x1.9
);

create type public.goal as enum ('perder_peso', 'mantener', 'ganar_peso');

create type public.meal_slot as enum ('desayuno', 'almuerzo', 'merienda', 'cena', 'snack');

-- Provenance matters for trust: the UI shows where each number came from.
create type public.data_source as enum (
  'off',      -- Open Food Facts bulk import
  'usda',     -- USDA FoodData Central (generic foods)
  'curated',  -- hand-entered and verified by us
  'user'      -- user-submitted, pending or approved
);

-- ---------------------------------------------------------------------------
-- Catalog
-- ---------------------------------------------------------------------------

create table public.brands (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  slug        text not null unique,
  logo_url    text,
  created_at  timestamptz not null default now()
);

create index brands_name_trgm_idx on public.brands using gin (immutable_unaccent(name) gin_trgm_ops);

-- Self-referencing for a shallow hierarchy: "Lácteos" > "Yogures".
create table public.categories (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,          -- Spanish, user-facing
  slug        text not null unique,
  parent_id   uuid references public.categories(id) on delete set null,
  sort_order  int not null default 0,
  created_at  timestamptz not null default now()
);

create index categories_parent_idx on public.categories(parent_id);

create table public.products (
  id                uuid primary key default gen_random_uuid(),
  name              text not null,
  brand_id          uuid references public.brands(id) on delete set null,
  category_id       uuid references public.categories(id) on delete set null,

  -- EAN-13/UPC. Argentine products under GS1 start with 779.
  barcode           text unique,

  -- Canonical basis for nutrition_facts: grams or millilitres.
  basis_unit        text not null default 'g' check (basis_unit in ('g', 'ml')),

  -- One serving in basis_unit (e.g. 200), plus how a person says it out loud
  -- (e.g. "1 vaso", "1 taza", "1 milanesa"). Both nullable: plenty of products
  -- have no meaningful single serving.
  serving_size      numeric(8,2) check (serving_size > 0),
  serving_label     text,

  source            public.data_source not null default 'curated',
  source_ref        text,                  -- upstream id, e.g. OFF barcode or USDA fdc_id
  is_verified       boolean not null default false,
  verified_at       timestamptz,

  -- Maintained by trigger below (includes brand name, so it cannot be a
  -- generated column).
  search_vector     tsvector,

  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index products_brand_idx     on public.products(brand_id);
create index products_category_idx  on public.products(category_id);
create index products_search_idx    on public.products using gin (search_vector);
create index products_name_trgm_idx on public.products using gin (immutable_unaccent(name) gin_trgm_ops);

-- Rebuild search_vector from the product name + its brand name.
-- Weight A = product name, B = brand: a query matching the name ranks higher.
create or replace function public.products_refresh_search_vector()
returns trigger
language plpgsql
as $$
declare
  brand_name text;
begin
  select b.name into brand_name from public.brands b where b.id = new.brand_id;

  new.search_vector :=
      setweight(to_tsvector('spanish', immutable_unaccent(coalesce(new.name, ''))), 'A')
   || setweight(to_tsvector('spanish', immutable_unaccent(coalesce(brand_name, ''))), 'B');

  new.updated_at := now();
  return new;
end;
$$;

create trigger products_search_vector_trg
  before insert or update of name, brand_id on public.products
  for each row execute function public.products_refresh_search_vector();

-- If a brand is renamed, refresh every product that references it.
create or replace function public.brands_cascade_search_vector()
returns trigger
language plpgsql
as $$
begin
  if new.name is distinct from old.name then
    update public.products set brand_id = brand_id where brand_id = new.id;
  end if;
  return new;
end;
$$;

create trigger brands_cascade_search_vector_trg
  after update of name on public.brands
  for each row execute function public.brands_cascade_search_vector();

-- 1:1 with products. Split out so the catalog table stays narrow and so a
-- product can exist while its panel is still being transcribed.
create table public.nutrition_facts (
  product_id        uuid primary key references public.products(id) on delete cascade,

  -- Per 100 basis_unit. The four the MVP actually renders:
  calories_kcal     numeric(7,2) not null check (calories_kcal >= 0),
  protein_g         numeric(7,2) not null default 0 check (protein_g >= 0),
  carbs_g           numeric(7,2) not null default 0 check (carbs_g   >= 0),
  fat_g             numeric(7,2) not null default 0 check (fat_g     >= 0),

  -- Present on every Argentine label since the 2021 front-of-pack law, so
  -- worth capturing at import time even though the MVP does not show them.
  saturated_fat_g   numeric(7,2) check (saturated_fat_g >= 0),
  fiber_g           numeric(7,2) check (fiber_g  >= 0),
  sugar_g           numeric(7,2) check (sugar_g  >= 0),
  sodium_mg         numeric(9,2) check (sodium_mg >= 0),

  updated_at        timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- User data
-- ---------------------------------------------------------------------------

create table public.profiles (
  id                uuid primary key references auth.users(id) on delete cascade,
  display_name      text,

  sex               public.sex,
  birth_date        date,
  height_cm         numeric(5,1) check (height_cm between 50 and 260),

  activity_level    public.activity_level not null default 'sedentario',
  goal              public.goal           not null default 'mantener',

  -- Calculated on onboarding (Mifflin–St Jeor x activity multiplier), then
  -- freely overridable — the plan treats the calculated value as a default,
  -- not a cage.
  calorie_target    int         check (calorie_target between 800 and 8000),
  protein_target_g  numeric(6,1) check (protein_target_g >= 0),
  carb_target_g     numeric(6,1) check (carb_target_g    >= 0),
  fat_target_g      numeric(6,1) check (fat_target_g     >= 0),

  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create table public.saved_meals (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  name        text not null,                     -- "mi desayuno de siempre"
  created_at  timestamptz not null default now()
);

create index saved_meals_user_idx on public.saved_meals(user_id);

create table public.saved_meal_items (
  id             uuid primary key default gen_random_uuid(),
  saved_meal_id  uuid not null references public.saved_meals(id) on delete cascade,
  product_id     uuid not null references public.products(id)    on delete restrict,
  quantity       numeric(8,2) not null check (quantity > 0),   -- in product.basis_unit
  unique (saved_meal_id, product_id)
);

create index saved_meal_items_meal_idx on public.saved_meal_items(saved_meal_id);

create table public.diary_entries (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  logged_on     date not null,
  meal_slot     public.meal_slot not null,

  product_id    uuid references public.products(id) on delete restrict,
  quantity      numeric(8,2) not null check (quantity > 0),    -- in product.basis_unit

  created_at    timestamptz not null default now()
);

-- The diary screen always queries "one user, one day", so lead with that.
create index diary_entries_user_date_idx on public.diary_entries(user_id, logged_on desc);

create table public.weight_logs (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  logged_on   date not null,
  weight_kg   numeric(5,2) not null check (weight_kg between 20 and 400),
  created_at  timestamptz not null default now(),
  unique (user_id, logged_on)                    -- one weigh-in per day, upsert to correct
);

create index weight_logs_user_date_idx on public.weight_logs(user_id, logged_on desc);

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

alter table public.brands           enable row level security;
alter table public.categories       enable row level security;
alter table public.products         enable row level security;
alter table public.nutrition_facts  enable row level security;
alter table public.profiles         enable row level security;
alter table public.saved_meals      enable row level security;
alter table public.saved_meal_items enable row level security;
alter table public.diary_entries    enable row level security;
alter table public.weight_logs      enable row level security;

-- Catalog: readable by anyone signed in. Writes go through the service role
-- (import jobs, moderation) — no client-side catalog edits in the MVP.
create policy "catalog readable" on public.brands
  for select to authenticated using (true);
create policy "catalog readable" on public.categories
  for select to authenticated using (true);
create policy "catalog readable" on public.products
  for select to authenticated using (true);
create policy "catalog readable" on public.nutrition_facts
  for select to authenticated using (true);

-- User data: owner-only, all verbs.
create policy "own profile" on public.profiles
  for all to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

create policy "own saved meals" on public.saved_meals
  for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

create policy "own diary entries" on public.diary_entries
  for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

create policy "own weight logs" on public.weight_logs
  for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- Items inherit ownership from their parent meal.
create policy "own saved meal items" on public.saved_meal_items
  for all to authenticated
  using (exists (
    select 1 from public.saved_meals m
    where m.id = saved_meal_id and m.user_id = (select auth.uid())
  ))
  with check (exists (
    select 1 from public.saved_meals m
    where m.id = saved_meal_id and m.user_id = (select auth.uid())
  ));

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
-- Two separate gates, easy to conflate: RLS decides *which rows* a caller may
-- touch, GRANT decides whether the table is reachable at all. A Supabase
-- project usually grants these implicitly through default privileges, but
-- spelling them out keeps this migration self-contained and portable.

grant usage on schema public to authenticated, service_role;

-- Catalog: read-only for clients. Imports and moderation run as service_role.
grant select on
  public.brands,
  public.categories,
  public.products,
  public.nutrition_facts
  to authenticated;

-- User-owned data: full CRUD, narrowed to their own rows by the RLS policies
-- above.
grant select, insert, update, delete on
  public.profiles,
  public.saved_meals,
  public.saved_meal_items,
  public.diary_entries,
  public.weight_logs
  to authenticated;

-- ---------------------------------------------------------------------------
-- Search entry point
-- ---------------------------------------------------------------------------

-- Two-pass search: exact-ish full-text first, trigram similarity as the
-- safety net for misspellings. Ranked so full-text hits win.
create or replace function public.search_products(q text, max_results int default 30)
returns table (
  product_id    uuid,
  name          text,
  brand_name    text,
  calories_kcal numeric,
  serving_size  numeric,
  serving_label text,
  rank          real
)
language sql
stable
as $$
  with normalised as (
    select immutable_unaccent(q) as term
  )
  select
    p.id,
    p.name,
    b.name,
    n.calories_kcal,
    p.serving_size,
    p.serving_label,
    greatest(
      ts_rank(p.search_vector, websearch_to_tsquery('spanish', (select term from normalised))),
      similarity(immutable_unaccent(p.name), (select term from normalised)) * 0.5
    ) as rank
  from public.products p
  left join public.brands b          on b.id = p.brand_id
  left join public.nutrition_facts n on n.product_id = p.id
  where
    p.search_vector @@ websearch_to_tsquery('spanish', (select term from normalised))
    or immutable_unaccent(p.name) % (select term from normalised)
  order by rank desc, p.is_verified desc, p.name
  limit max_results;
$$;

grant execute on function public.search_products(text, int) to authenticated;
