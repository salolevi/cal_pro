# CalorAR — Product & Build Plan

*Working title — swap it for whatever clicks. Every duration below is a planning estimate, not a commitment.*

**Context:** Solo build · iOS first · Portfolio project · Native Swift

Full version with styling/visual roadmap: https://claude.ai/code/artifact/0d0303ad-6364-41c6-8584-e46e126c3690

---

## The bet

Global calorie apps — MyFitnessPal, Yazio, Lifesum, Cronometer — treat Argentina as an afterthought. Their catalogs skew toward US and European packaged goods, and even where a local product exists, it's often a crowdsourced entry with the wrong serving size or a translated-but-wrong nutrition panel. The wedge here isn't a new tracking mechanic; it's owning the unglamorous part competitors underinvest in — an accurate, Spanish-native catalog of what Argentines actually eat, from Arcor and La Serenísima down to a milanesa that never came in a package.

Because this is a solo, iOS-first, portfolio-flavored build, the plan below is sequenced so the riskiest assumption — *does catalog quality actually matter enough to keep someone logging?* — gets tested in front of real users before any secondary feature gets built.

## Tech stack

Chosen for one person to move fast on, without boxing in the parts of the app that are actually hard — the catalog and its search.

### Client

| Layer | Choice | Why |
|---|---|---|
| UI framework | Swift + SwiftUI | iOS-only for v1 removes the cross-platform tax entirely; native gives the smoothest animations and is the stronger portfolio signal for iOS roles. |
| Local storage | SwiftData (iOS 17+) | Modern on-device store built for SwiftUI; keeps meal logging usable without a live connection. |
| Concurrency | Swift Concurrency | Built into the language, no extra dependency, pairs cleanly with Supabase's Swift client. |
| Health integration | HealthKit *(fast-follow)* | Native access to weight and activity data once the core loop is validated. |

### Backend

| Layer | Choice | Why |
|---|---|---|
| Database & API | Supabase (Postgres) | The catalog is relational by nature — brand → product → nutrition facts. Postgres full-text and trigram search handle accented, typo-prone Spanish queries far better than a document store. |
| Auth | Supabase Auth | Email + Sign in with Apple. Apple requires Sign in with Apple once any other third-party login is offered, so it's built in from day one, not retrofitted. |
| File storage | Supabase Storage | Product images and brand logos, same project, one vendor to manage. |
| Server logic | Supabase Edge Functions | Reserved for what shouldn't run on-device: bulk catalog imports, moderating user-submitted products. |

### Supporting tools

| Layer | Choice | Why |
|---|---|---|
| Analytics | TelemetryDeck | Built for indie iOS apps, privacy-respecting, priced for a passion project. |
| Crash reporting | Xcode Organizer → Sentry later | Don't add a dependency before the volume justifies it. |
| CI/CD | Xcode Cloud | Zero-config with Xcode and App Store Connect; the free tier comfortably covers a solo cadence. |
| Design | Figma | Free tier; forces a wireframe pass before screens get built. |
| Source control | GitHub, private repo | Free, and doubles as a portfolio artifact if it's later made public. |

**Alternative considered — Firebase.** Easier iOS SDK, more mature real-time sync. But Firestore's document model fights the relational catalog queries this app depends on, like "products from Brand X, sorted by protein." Worth a second look only if the catalog model ends up much simpler than planned.

## Data strategy — the real product

The app is a thin shell around this. Four sourcing lanes, in the order they should actually get built:

- **A · Bulk import** — Open Food Facts: free, open, crowdsourced, with an Argentina subset filterable by country tag or by the 779 barcode prefix Argentina uses under the GS1 system. Immediate baseline coverage; treat it as a floor, not the final answer, since quality is uneven. **Licence: ODbL 1.0 for the database** (share-alike applies to derived databases), Database Contents License for individual facts, CC-BY-SA for images — see [docs/off-coverage.md](docs/off-coverage.md). *Verified 2026-08-16: 15,777 Argentina products, ~69% usable, all 20 major national brands present.*
- **B · Curated top brands** — Hand-enter and verify the ~150–300 highest-volume Argentine products: Arcor, Bagley, La Serenísima, Molinos, Georgalos, Manaos, Quilmes, and similar household names. Most logging happens against a small, repeated set of products, so accuracy here beats long-tail breadth.
- **C · Generic & home-cooked foods** — Import USDA FoodData Central for the universal staples (fruit, vegetables, meat, grains) and relabel it in Argentine terms and everyday units: taza, milanesa, bife, not literal US serving sizes.
- **D · Crowdsourcing loop** — Post-launch "can't find it? add it" flow: a photo of the nutrition table plus manual entry, queued for approval. Argentina's 2021 front-of-package labeling law means virtually every packaged product now carries a standardized nutrition table, which makes this easier to crowdsource than in markets without that standard.

**Sequencing:** B and C need to exist before the app is demoable at all. A can run as a background import job in parallel. D only starts paying off once there are real users — building it pre-launch would be solving a problem you don't have yet.

## Scope

The "standard" tier: a lean core plus weight tracking, editable goals, and saved meals. Everything else is explicitly sequenced, not cut.

| Feature | Tier | Notes |
|---|---|---|
| Sign up / sign in (email + Sign in with Apple) | MVP | — |
| Profile & goal setup | MVP | Sex, age, height, weight, activity level, goal |
| Auto-calculated calorie & macro targets | MVP | Mifflin–St Jeor for BMR, activity multiplier for TDEE |
| Editable calorie target & macro split | MVP | Overrides the calculated default |
| Catalog search | MVP | Spanish, accent- and typo-tolerant — the core differentiator |
| Generic / home-cooked food logging | MVP | Non-branded staples |
| Meal diary | MVP | Desayuno / Almuerzo / Merienda / Cena, running totals vs. targets |
| Favorites & recently logged | MVP | Speeds up repeat logging |
| Weight log + trend chart | MVP | — |
| Saved meals | MVP | e.g. "mi desayuno de siempre," one-tap logging |
| History / calendar + weekly averages | MVP | — |
| Barcode scanning | Fast-follow | AVFoundation/VisionKit; big UX win, deliberately just outside MVP |
| Local reminder notifications | Fast-follow | UserNotifications, no backend needed |
| HealthKit sync | Fast-follow | Weight & active energy |
| User-submitted products | Later | Needs a real user base to justify the moderation overhead |
| Social / friends / sharing | Later | — |
| Meal planning & suggestions | Later | — |
| Android app | Later | Only if iOS validates the core bet |
| Restaurant / menu database | Later | Large enough to be its own separate bet |

## Data model

Deliberately small. Three groups, nine entities — enough to build the MVP scope above without redesigning the schema halfway through.

**Identity**
- `User` — auth identity
- `Profile` — biometrics, activity level, goal, computed targets

**Catalog**
- `Brand` — name, logo
- `Product` — name, brand, category, serving size
- `NutritionFact` — calories, protein, carbs, fat per 100g/serving
- `Category` — for browsing and filtering

**Logging**
- `DiaryEntry` — user + product/meal + quantity + meal slot + date
- `SavedMeal` — user-defined, reusable group of products
- `WeightLog` — user + date + value

## Roadmap

Seven phases from empty repo to App Store. Durations are planning estimates for full-time (FT) vs. part-time at 10–15 hrs/week (PT).

| Phase | What | Duration |
|---|---|---|
| 0 — Foundations | Repo, Xcode project, Supabase project, schema draft, core-screen wireframes | FT 1wk · PT 2–3wk |
| 1 — Catalog bootstrap | Open Food Facts import, top-brand curation, generic foods. Runs partly alongside Phase 2 | FT 1–2wk · PT 3–4wk |
| 2 — Core app build | Onboarding, goal calculator, search, diary, weight log, saved meals, history | FT 3–4wk · PT 8–10wk |
| 3 — Polish & QA | Empty states, error handling, accessibility pass, App Store screenshots and copy | FT 1wk · PT 2wk |
| 4 — TestFlight beta | 5–10 real Argentine users log real meals — where the catalog bet actually gets tested | 2–4wk, either pace |
| 5 — Launch | Submit for App Store review, address feedback, ship | ~1wk, mostly review wait |
| 6 — Fast-follows | Barcode scanning, HealthKit, reminders — then decide on Android from real usage data | Ongoing |

Rough total to launch: **8–10 weeks full-time**, or **4–5 months part-time**. Phase 4 compresses that gap somewhat — it's calendar-bound (waiting on real usage), not effort-bound, so it costs part-time builders relatively less than the earlier phases do.

## Risks & open questions

- **The catalog is the real risk, not the tracking UX.** A beautiful app with a thin catalog loses to a plain app with a complete one. Validate coverage with real users in Phase 4 before polishing anything further.
- **Solo moderation load.** The crowdsourcing "add a product" flow can quietly turn into an unpaid part-time job. Keep it manual and low-volume until it's clearly worth automating.
- **Data accuracy & liability.** Show each product's data source and last-updated date, and add a plain disclaimer that the app isn't medical advice.
- **iOS-only ceiling.** Android holds the large majority of the Argentine mobile market, so an iOS-only launch caps the addressable audience by design. That's a fine tradeoff for cheaply validating the catalog bet as a solo dev — worth revisiting only if this grows past a portfolio project.

## Immediate next steps

1. Create a private GitHub repo and a fresh SwiftUI Xcode project.
2. Spin up a Supabase project; draft the Brand / Product / NutritionFact / Category schema.
3. Pull an Open Food Facts data export, filter to Argentina, and actually look at how good the coverage is before committing to it as the base layer.
4. Hand-curate the first ~50 highest-frequency products so UI work isn't blocked on the full import pipeline.
5. Wireframe five core screens in Figma: onboarding, search, product detail, diary, profile/goals.
