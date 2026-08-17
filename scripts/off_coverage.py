#!/usr/bin/env python3
"""Assess Open Food Facts coverage for Argentina.

A raw product count says nothing about whether the data is usable. This samples
the Argentina subset and measures what fraction actually carries the fields
CalorAR needs: a name, a brand, energy, and all four macros.
"""

import json, time, subprocess, collections, statistics, sys

UA = "CalorAR-CoverageCheck/0.1 (github.com/salolevi/cal_pro)"
BASE = "https://world.openfoodfacts.org/api/v2/search"
FIELDS = ",".join([
    "code", "product_name", "brands", "brands_tags", "quantity",
    "serving_size", "serving_quantity", "nutriments", "categories_tags",
    "completeness", "last_modified_t",
])
PAGES = 12
PAGE_SIZE = 100


def fetch(page):
    # curl rather than urllib: this Python has no CA bundle configured, and
    # curl uses the system trust store.
    url = (f"{BASE}?countries_tags_en=argentina&fields={FIELDS}"
           f"&page_size={PAGE_SIZE}&page={page}")
    out = subprocess.run(
        ["curl", "-s", "-m", "90", "-A", UA, url],
        capture_output=True, text=True, check=True,
    ).stdout
    return json.loads(out)


products, total = [], None
for page in range(1, PAGES + 1):
    for attempt in range(3):
        try:
            data = fetch(page)
            break
        except Exception as e:
            if attempt == 2:
                print(f"  page {page} failed: {e}", file=sys.stderr)
                data = {"products": []}
            time.sleep(8)
    total = total or data.get("count")
    got = data.get("products", [])
    products.extend(got)
    print(f"  page {page}: {len(got)} products", file=sys.stderr)
    if len(got) < PAGE_SIZE:
        break
    time.sleep(6)          # stay inside the search endpoint's rate limit

n = len(products)
print(f"\n{'='*58}\nSAMPLE: {n} of {total} Argentina products\n{'='*58}")


def has(p, key):
    v = p.get(key)
    return bool(v) and str(v).strip() not in ("", "unknown")


def nutri(p, key):
    v = p.get("nutriments", {}).get(key)
    return isinstance(v, (int, float))


MACROS = ["proteins_100g", "carbohydrates_100g", "fat_100g"]

stats = {
    "has name":            sum(has(p, "product_name") for p in products),
    "has brand":           sum(has(p, "brands") for p in products),
    "has energy (kcal)":   sum(nutri(p, "energy-kcal_100g") for p in products),
    "has all 3 macros":    sum(all(nutri(p, m) for m in MACROS) for p in products),
    "has serving_size":    sum(has(p, "serving_size") for p in products),
    "has category":        sum(bool(p.get("categories_tags")) for p in products),
}

# The bar that actually matters: could this row be shown in the app as-is?
usable = sum(
    1 for p in products
    if has(p, "product_name")
    and nutri(p, "energy-kcal_100g")
    and all(nutri(p, m) for m in MACROS)
)
usable_branded = sum(
    1 for p in products
    if has(p, "product_name") and has(p, "brands")
    and nutri(p, "energy-kcal_100g")
    and all(nutri(p, m) for m in MACROS)
)

print("\nFIELD COMPLETENESS")
for k, v in stats.items():
    print(f"  {k:<22} {v:>5} / {n}   {v/n*100:>5.1f}%")

print("\nUSABLE ROWS  (name + kcal + protein + carbs + fat)")
print(f"  usable                 {usable:>5} / {n}   {usable/n*100:>5.1f}%")
print(f"  usable AND branded     {usable_branded:>5} / {n}   {usable_branded/n*100:>5.1f}%")
print(f"\n  extrapolated to {total}: ~{int(total*usable/n):,} usable, "
      f"~{int(total*usable_branded/n):,} usable+branded")

# Which brands actually dominate?
brands = collections.Counter()
for p in products:
    for b in (p.get("brands_tags") or []):
        brands[b] += 1

print("\nTOP 25 BRANDS IN SAMPLE")
for b, c in brands.most_common(25):
    print(f"  {c:>4}  {b}")

# Do the brands the plan names actually show up?
KEY = ["arcor", "la-serenisima", "bagley", "molinos", "georgalos", "manaos",
       "quilmes", "knorr", "danone", "sancor", "terrabusi", "havanna",
       "villavicencio", "coca-cola", "nestle", "ledesma", "marolio", "bimbo"]
print("\nPLAN-NAMED BRANDS — presence in sample")
for k in KEY:
    c = brands.get(k, 0)
    print(f"  {k:<16} {c:>4} {'✓' if c else '—'}")

comp = [p["completeness"] for p in products if isinstance(p.get("completeness"), (int, float))]
if comp:
    print(f"\nOFF 'completeness' score: median {statistics.median(comp):.2f}, "
          f"mean {statistics.mean(comp):.2f}")

stale = sum(1 for p in products
            if isinstance(p.get("last_modified_t"), int)
            and p["last_modified_t"] < time.time() - 3 * 365 * 86400)
print(f"Not updated in 3+ years: {stale}/{n} ({stale/n*100:.1f}%)")

with open("/private/tmp/claude-501/-Users-salomongiorgioleviaparain-Dev-cal-pro/"
          "ef94d8aa-a39d-4d94-97c3-9ac2cfcefe63/scratchpad/off_sample.json", "w") as f:
    json.dump(products, f)
print(f"\nRaw sample saved ({n} products).")
