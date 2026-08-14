-- Seed a handful of real Argentine products, then exercise search.

insert into public.brands (name, slug) values
  ('La Serenísima', 'la-serenisima'),
  ('Arcor',         'arcor'),
  ('Bagley',        'bagley'),
  ('Quilmes',       'quilmes');

insert into public.categories (name, slug) values
  ('Lácteos',   'lacteos'),
  ('Galletitas','galletitas'),
  ('Bebidas',   'bebidas');

insert into public.products (name, brand_id, category_id, basis_unit, serving_size, serving_label, barcode, source, is_verified)
values
  ('Leche Entera La Serenísima',
     (select id from public.brands where slug='la-serenisima'),
     (select id from public.categories where slug='lacteos'),
     'ml', 200, '1 vaso', '7790742000017', 'curated', true),
  ('Yogur Entero Frutilla',
     (select id from public.brands where slug='la-serenisima'),
     (select id from public.categories where slug='lacteos'),
     'g', 190, '1 pote', '7790742000024', 'curated', true),
  ('Galletitas Criollitas',
     (select id from public.brands where slug='bagley'),
     (select id from public.categories where slug='galletitas'),
     'g', 30, '6 galletitas', '7790040000031', 'curated', true),
  ('Alfajor Bon o Bon',
     (select id from public.brands where slug='arcor'),
     (select id from public.categories where slug='galletitas'),
     'g', 45, '1 alfajor', '7790040000048', 'curated', true),
  ('Cerveza Quilmes Clásica',
     (select id from public.brands where slug='quilmes'),
     (select id from public.categories where slug='bebidas'),
     'ml', 355, '1 lata', '7790070000055', 'curated', true);

insert into public.nutrition_facts (product_id, calories_kcal, protein_g, carbs_g, fat_g)
select id,
  case
    when name like 'Leche%'      then 61
    when name like 'Yogur%'      then 79
    when name like 'Galletitas%' then 456
    when name like 'Alfajor%'    then 510
    else 43
  end,
  3.0, 8.0, 3.0
from public.products;

\echo ''
\echo '=== 1. accent-insensitive: "serenisima" (no accent) should find La Serenísima ==='
select name, brand_name, round(rank::numeric, 4) as rank from public.search_products('serenisima');

\echo ''
\echo '=== 2. plain term: "yogur" ==='
select name, brand_name, round(rank::numeric, 4) as rank from public.search_products('yogur');

\echo ''
\echo '=== 3. typo tolerance: "galletitas" -> "galetitas" (missing l) ==='
select name, brand_name, round(rank::numeric, 4) as rank from public.search_products('galetitas');

\echo ''
\echo '=== 4. Spanish stemming: "cervezas" (plural) should match "Cerveza" ==='
select name, brand_name, round(rank::numeric, 4) as rank from public.search_products('cervezas');

\echo ''
\echo '=== 5. multi-word: "leche entera" ==='
select name, brand_name, round(rank::numeric, 4) as rank from public.search_products('leche entera');

\echo ''
\echo '=== 6. brand-name search: "arcor" should surface Bon o Bon via brand weight ==='
select name, brand_name, round(rank::numeric, 4) as rank from public.search_products('arcor');

\echo ''
\echo '=== 7. brand rename cascade: rename Bagley -> Bagley SA, then search it ==='
update public.brands set name = 'Bagley SA' where slug = 'bagley';
select name, brand_name, round(rank::numeric, 4) as rank from public.search_products('bagley sa');

\echo ''
\echo '=== 8. per-serving derivation (kcal per serving from per-100 basis) ==='
select p.name, n.calories_kcal as per_100, p.serving_size, p.serving_label,
       round(n.calories_kcal * p.serving_size / 100, 1) as kcal_per_serving
from public.products p join public.nutrition_facts n on n.product_id = p.id
order by p.name;
