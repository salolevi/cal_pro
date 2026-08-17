# Open Food Facts — Argentina coverage assessment

*Run 2026-08-16. Method: OFF API v2, `countries_tags_en=argentina`, 1,000-product
random-ordered sample (6.3% of the set). Script: `scripts/off_coverage.py`.*

## Verdict

**The catalog bet is viable.** OFF carries enough usable Argentine data to be a
real base layer, and every major national brand is present. The gap is accuracy
on high-traffic products, not breadth — which is what hand-curation was always
meant to solve.

## Headline numbers

| Metric | Result |
|---|---|
| Products tagged Argentina | **15,777** |
| Usable (name + kcal + protein + carbs + fat) | **69.0%** → ~10,900 |
| Usable **and** branded | **67.2%** → ~10,600 |
| Has a brand | 90.0% |
| Has serving size | 73.8% |
| Has a category | 84.5% |
| Not updated in 3+ years | 8.0% |
| OFF "completeness" score | median 0.70 |

~10,600 usable branded products is a substantial starting catalog — for
comparison, the plan's hand-curation target was 150–300 products.

## Brand coverage

All 20 major Argentine brands checked appear in a 6.3% sample, which strongly
implies full coverage across the whole set.

| Brand | In sample | Brand | In sample |
|---|---|---|---|
| Arcor | 67 | Bimbo | 9 |
| La Serenísima | 49 | Don Satur | 9 |
| Granix | 25 | La Campagnola | 8 |
| La Virginia | 22 | Matarazzo | 7 |
| Coca-Cola | 18 | Manaos | 6 |
| Bagley | 17 | Cachafaz | 6 |
| Tregar | 14 | Georgalos, Sancor, Ledesma, Marolio | 3 each |
| Terrabusi | 10 | Molinos, Quilmes, Havanna | 1 each |

## The finding that changes the import pipeline

**Brand names are not normalised in OFF, and the variance is severe.**

"La Serenísima" appears under **seven** distinct spellings in a single
1,000-product sample:

```
LA SERENISIMA · La  Serenísima · La Serenisima · La Serenísima
La serenisima · La serenísima  · la serenisima
```

Across the sample, 483 raw brand strings collapse to **403** after
case-folding and accent-stripping — 16.6% are duplicates. Imported naively,
the app would show seven "La Serenísima" brands and split their products
across all of them.

The schema already anticipates this: `brands.slug` is `unique`, so the
importer must slug-normalise (lowercase, strip accents, collapse
non-alphanumerics) and upsert on `slug` rather than `name`. Keep the most
frequent spelling as the display `name`.

The same normalisation is already used at query time by
`immutable_unaccent()`, so search and import agree.

## Caveats

- **Sample, not census.** 1,000 of 15,777. Percentages carry roughly ±3pp at
  95% confidence; brand presence is a lower bound, not a count.
- **"Usable" is a floor, not a quality claim.** It means the four fields are
  present and numeric. It does *not* mean they are correct. Crowdsourced entries
  carry transcription errors, and this measurement cannot detect them — which is
  exactly why `is_verified` exists and why the top products get hand-checked.
- **One request failed** (page 11 returned a non-JSON response). The sample is
  1,000 rather than the intended 1,200. No reason to think it biases the result.
- **Serving sizes are free text.** `serving_size` is 73.8% present but holds
  strings like "1 vaso (200 ml)" and "30 g". Parsing them into
  `serving_size numeric` + `serving_label text` is real import work, and the
  26% without one need the per-100 fallback.

## Licensing — read before commercialising

**The Open Food Facts database is ODbL 1.0, not CC-BY-SA.** An earlier draft of
`PLAN.md` said CC-BY-SA; that was wrong and is corrected.

- **Database**: Open Database License (ODbL) 1.0 — **share-alike on derived
  databases**
- **Individual contents/facts**: Database Contents License
- **Product images**: CC-BY-SA

A Postgres catalog built by importing OFF is a derived database. ODbL's
share-alike obligation attaches when a derived database is publicly used, which
can mean publishing your version of the data under ODbL too. This is fine for a
portfolio project and needs real legal reading before any commercial launch.

Mixing hand-curated rows with OFF-derived rows in one table makes the boundary
harder to draw later. The `source` column already distinguishes them, which
helps, but it is worth deciding early whether curated data stays separable.

## FatSecret — assessed and not recommended as a catalog source

Their [API terms](https://platform.fatsecret.com/terms) settle it:

> "You may not continue to use and must immediately remove or replace any
> Content in your possession … not explicitly identified as being storable
> indefinitely **within 24 hours**"

Plus: attribution required everywhere content is displayed, and 5,000 API
calls/day across all tiers.

This makes FatSecret a **query-time source, not a catalog source**. You cannot
import it into `products` and keep it. Using it would mean a live API proxy with
a 24-hour cache ceiling — a different architecture, and one that inverts the
product thesis of *owning* an accurate Argentine catalog.

It is also unnecessary: OFF already delivers ~10,600 usable branded Argentine
products, and 5,000 calls/day would not survive search-as-you-type.

### Sources that *can* be bulk-imported

| Source | Licence | Verdict |
|---|---|---|
| Open Food Facts | ODbL (share-alike) | ✅ base layer — confirmed viable |
| USDA FoodData Central | Public domain | ✅ generic foods, already planned |
| Hand-curated | Yours | ✅ top products, highest value per row |
| FatSecret | Proprietary, 24h deletion | ❌ cannot build a catalog from it |

## Recommended next steps

1. Build the importer with slug-normalised brand upsert as a first-class
   concern, not an afterthought.
2. Import only rows meeting the usable bar; leave the other 31% out rather than
   shipping blank nutrition panels.
3. Mark every imported row `source = 'off'`, `is_verified = false`. Hand-curation
   flips the flag.
4. Write the free-text `serving_size` parser with a fallback path, and expect it
   to be the fiddliest part of the import.
5. Revisit ODbL obligations if this ever stops being a portfolio project.
