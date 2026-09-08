---
status: raw
effort: 1-2 days
created: 2026-02-14
updated: 2026-09-07
epic: cynipid
docs: ['']
relates: [85c0]
---

# Investigate Adam's phenology tool

GitHub: https://github.com/Megachile/Phenology

Goals:
- Get it primed for use with Claude Code (CLAUDE.md, documentation, etc.)
- Understand what it does and how it works
- Evaluate the codebase quality and architecture
- Propose a path forward: fold into gallformers codebase vs. integrate at some level

## Product exploration (2026-02-16)

Phenology data is one dimension of a larger cynipid product vision for Gallformers. iNat observations serve as a foundational data layer feeding three dimensions: phenology timing, fine-grained range, and abundance signal. Combined with existing host associations and future adult anatomy data, this enables:

1. Enriched species profiles — location-aware, temporally-aware pages
2. Collection/field planning — when and where to find target species
3. Field trip optimization — what's active near me on a given date
4. Improved gall-first ID — phenology as a filter to narrow candidates
5. New organism-first ID pathway — adult anatomy (via keys) + phenology + host narrows to species without seeing a gall

Keys play a dual role: navigation for users AND structured anatomy data source. Building adult cynipid keys and building the anatomy dataset are the same effort.

Scope is cynipid-only for now. Patterns could extend to other groups later.

Design doc: docs/plans/2026-02-16-cynipid-phenology-product-vision.md

## Product Vision

Gallformers evolves from a static reference into a location-aware, temporally-aware species resource for cynipid gall wasps. Users can plan field work, understand what's active near them, and — as anatomy data matures — identify adult wasps without seeing a gall.

### Data Foundations

A single foundational data layer — iNaturalist observations — feeds multiple product dimensions:

| Dimension | What it provides | Status |
|-----------|-----------------|--------|
| Phenology | When each species/generation/phenophase is active at a given latitude | Available (Phenology tool) |
| Fine-grained range | Actual occurrence points, not broad geographic labels | Available (iNat observations) |
| Abundance signal | Observation density as a proxy for commonality in an area | Available (iNat observations) |
| Host associations | Which plants a species is found on | Available (Gallformers core data) |
| Adult anatomy | Structured morphological traits of adult wasps | Future — see Keys connection |

### Use Cases

1. **Enriched species profiles** — Activity windows by phenophase/generation at user's latitude, occurrence map, seasonal context
2. **Collection and field planning** — Predicted date ranges for rearing-viable galls at a given latitude
3. **Field trip optimization** — All species with predicted activity overlapping user's date and location
4. **Gall-first ID (improved)** — Phenology as additional filter in existing ID workflow, weighting candidates by plausible activity
5. **Organism-first ID (new)** — Identify adult cynipid without seeing its gall, combining phenology + host + adult anatomy. Each dimension alone is broad, but intersection can be razor sharp (e.g., wingless adult on Q. garryana in February = one species)

### Keys as dual-role

Keys serve as both navigation (walk user through couplets) and data source (couplets encode structured anatomy data). Building adult cynipid keys and building the anatomy dataset are the same effort.

### Scope

Cynipid-only. Generation alternation creates distinct phenological patterns, phenology dataset exists, adult ID is a real unmet need (many unidentified iNat observations of wasps). Patterns could extend to other groups later.

### Open Questions

- **Data boundary**: Where does Adam's curation/modeling end and Gallformers' consumption begin?
- **Update cadence**: Real-time vs periodic sync affects architecture significantly
- **Abundance methodology**: Raw observation counts are noisy — what normalization needed?
- **Anatomy data collection**: Manual from literature, iNat photos, expert contribution, or combination?
- **Geographic scope**: Phenology tool has best coverage in North America — interaction with hemisphere expansion?


---

## Full Vision Document

# Cynipid Phenology & iNat Integration — Product Vision

## Problem

Gallformers today is a reference database: it tells you what a gall looks like, what species makes it, and what host it grows on. This is valuable but static. Users who want to *find* galls — researchers planning collection trips, people trying to rear wasps, naturalists hunting rare species — get no help with the questions "when?" and "where, specifically?"

Meanwhile, a separate phenology tool (Adam Kranz's Phenology project) already answers "when will species X be active at latitude Y?" for cynipid gall wasps, using iNaturalist observations normalized by a Season Index metric. But it lives outside Gallformers with no integration beyond a link.

## Vision

For cynipid gall wasps, Gallformers evolves from a static reference into a location-aware, temporally-aware species resource. Users can plan field work, understand what's active near them right now, and — as anatomy data matures — identify adult wasps without ever seeing a gall.

## Data Foundations

A single foundational data layer — **iNaturalist observations** — feeds multiple product dimensions:

| Dimension | What it provides | Status |
|-----------|-----------------|--------|
| **Phenology** | When each species/generation/phenophase is active at a given latitude | Available (Phenology tool) |
| **Fine-grained range** | Actual occurrence points, not broad geographic labels | Available (iNat observations) |
| **Abundance signal** | Observation density as a proxy for commonality in an area | Available (iNat observations) |
| **Host associations** | Which plants a species is found on | Available (Gallformers core data) |
| **Adult anatomy** | Structured morphological traits of adult wasps | Future — see Keys connection below |

## Use Cases

### 1. Enriched species profiles

Species pages gain temporal and geographic depth. Instead of just "this species exists and looks like this," a cynipid profile shows:

- Predicted activity windows by phenophase and generation at the user's latitude
- Where it has actually been observed (map of occurrence points)
- How common or rare it is in different areas
- Seasonal context: "right now, this species is likely in the dormant phase at your location"

### 2. Collection and field planning

For researchers and rearers who go out *looking* for specific species:

- "When should I go to collect *Andricus quercuscalifornicus* for rearing in Michigan?" — predicted date range for rearing-viable galls at that latitude
- "What's the current phenophase of species X where I am?" — so you know what to expect in the field

### 3. Field trip optimization

Flipping the direction — starting from a time and place rather than a target species:

- "I'm going out this Saturday near Portland. What cynipid species should be active?" — all species with predicted activity overlapping the user's date and location
- "What else might I find while I'm looking for species X on these oaks?" — serendipity planning

### 4. Gall-first identification (existing pathway, improved)

Phenology as an additional filter in the existing ID workflow. When a user is trying to identify a gall, the system can weight candidates by whether they are plausibly active at the user's time and location. This doesn't replace morphological ID — it sharpens it.

### 5. Organism-first identification (new pathway)

A fundamentally new capability: identifying an adult cynipid wasp without seeing its gall. This combines:

- **Phenology** narrows the time window — what species are active now, here
- **Host association** narrows the plant — what's associated with this oak species
- **Adult anatomy** narrows the organism — wingless/winged, body color, size, etc.

Each dimension alone is broad, but the intersection can be razor sharp. Example: "a wingless adult wasp on *Quercus garryana* in February" points to one and only one species.

### Keys as both navigation and data source

Identification keys are central to the organism-first pathway. They serve a dual role:

- **Navigation**: Keys walk a user through structured decisions (couplets) to reach an identification. Combined with phenology and host filters to pre-narrow the candidate set, keys become the interface for organism-first ID.
- **Data source**: The couplets in an adult cynipid key *are* the structured anatomy data. "Is the wasp wingless or winged?" encodes a trait. Building the keys and building the anatomy dataset are the same effort.

This means the existing keys feature work has a direct line to enabling organism-first identification. The keys infrastructure is already being built.

## Scope

This vision is **cynipid-scoped**. Cynipid gall wasps are special in several ways that make this feasible:

- Generation alternation (sexual/agamic) creates distinct, predictable phenological patterns
- The phenology dataset already exists with meaningful coverage
- Adult identification is a real unmet need (many iNat observations of unidentified wasps)

The patterns established here — iNat data integration, phenology modeling, keys-as-structured-data — could extend to other gall-former groups later, but that is not in scope.

## Open Questions

- **Data boundary**: Where does Adam's curation/modeling workflow end and Gallformers' consumption begin? This depends on how the phenology tool evolves and how Adam works. Not yet decided.
- **Update cadence**: How frequently does Gallformers need refreshed phenology/iNat data? Real-time vs. periodic sync affects architecture significantly.
- **Abundance methodology**: Raw observation counts are a noisy abundance proxy. What normalization (if any) is needed to be useful rather than misleading?
- **Anatomy data collection**: How will adult anatomy traits be gathered initially? Manual entry from literature, extraction from iNat photos, expert contribution, or some combination?
- **Geographic scope**: The phenology tool currently has best coverage in North America. How does this interact with the Western Hemisphere expansion plans?

## Release implementation (2026-09-07)

The `phenology-release` branch is rebuilt on current upstream main, without the
experimental branch history. It contains the public explorer, a lazy per-gall
panel, and one shared context/model/result-component path. The original local
prototype is preserved separately.

- Fresh-gall onset uses the earliest seasonally normalized developing record,
  with one line/date and a source-linked anchor, replacing the initial q05–q10
  estimate. This relies on curated stage labels, not an automatic credibility
  classification. Emergence pools maturing and
  Free-living. Viable collection uses explicit viability regardless of phase.
  Event toggles and visible observation stages are independent. Prediction lines
  and date markers on the plot persist when changing the panel below the chart.
  That selector still chooses Predictions (text), Data table, or Species list;
  it never controls plot visibility.
- Selected species pool within generation. One shared quarter-degree 25–55°N
  thermal-landmark reference supplies both lines and date outputs. Legacy seasind
  remains only as an optional selection lens, not a second prediction model.
- Gall pages do no phenology query until expansion, then reuse loaded evidence.
  Full-chart links preserve exact GF identity and latitude. Both views use the
  same date renderer and plain-language warnings for few records, limited
  latitude coverage and extrapolation beyond the actual recorded latitude range.
  Geographic-cell counts remain model metadata, not public-facing terminology.
- Ordinary queries use Ecto; recursive taxonomy/place CTEs retain explicit SQL.
  Operational failures propagate instead of masquerading as an empty dataset.
- One reversible migration creates empty evidence/blacklist tables. It contains
  no imports, relabeling or source-metadata mutation. R/Python curation, literature
  intake, perimature review heuristics, regional climate experiments, local server
  settings and observation snapshots are outside this PR.
- The prescreen also fixed cold-start event parsing, unsafe external table-link
  protocols, a shared toggle CSS cascade conflict, and mobile chart sizing.

Verification: `mix precommit` (2,196 tests, zero failures; normal excluded tags),
Dialyzer (zero errors), JavaScript tests (180 passing), assets build, fresh-table
migration and rollback, and desktop/mobile browser checks. Both views return
identical dates; visibility and event toggles operate independently; table
sorting works. Fifty-four event/latitude comparisons across D. quercuspalustris,
Eurosta solidaginis and four Disholcaspis species match the prototype's dates and
evidence counts at the initial refactor checkpoint, before the intentional onset
change above. This is refactor parity, not additional ecological validation.

Per-gall scope audit: the preserved prototype also showed a source-count breakdown
and independent stage IQRs (raw dates without a target latitude, seasind-adjusted
with one). The shared three-event compact panel replaced those stage windows and
omitted the source breakdown. The older data-layer proposal described an embedded
scatter chart and filters; that was not present in the preserved summary
component. These are real scope differences, not just a code-only refactor.
Restoring descriptive context or an embedded chart needs a separate UI decision;
do not silently restore the obsolete stage-duration model.

Onset/coverage follow-up verification: `mix precommit` (2,205 tests, zero failures;
84 standard exclusions), Dialyzer (zero errors), 182 JavaScript tests, assets build
and desktop/mobile browser checks pass. All 36 emergence/rearing comparisons
retain prototype dates/counts. D. cinerosa onset at 30°N now uses the July 15
records rather than the August q05; the several same-date/location observations
count as one replicate. Tests cover normalized rather than raw-date ranking,
winter onset, later-record dominance, reproducible anchors and warning cutoffs.

### Northern-onset diagnosis after review

Adam reports that the new D. quercuspalustris onset is implausibly early in the
north. Read-only audit of the current snapshot supports a latitude-transfer
problem: one March 15, 2023 record at 34.551°N (iNat 151319576) sets the entire
curve. At 40°N it predicts April 2, versus April 14 for the earliest record
within ±2° after clock normalization (393 date/location records, ten years).
At 45°N it predicts April 13 versus May 10 (55 records, seven years). The prior
global q05 gave April 23 and May 7 respectively. These are descriptive comparisons
of positive records, not absence-based proof of biological onset. Coverage near
48°N is only one record; there are none within ±2° of 50°N.

A total-count switch from minimum to q05 is not a sufficient fix: D. cinerosa
has 282 developing records, yet its informative July 15 anchor is swamped by
late records and q05 moves to August. Proposed next step, not implemented or
validated: keep the shared clock as the sparse-data fallback, but allow a smooth
latitude-dependent correction from independent local leading-edge evidence where
available. Local onset information, rather than total developing observations,
must control the weight. Credible early records constrain their own local timing,
not every latitude; local first-positive dates can still be delayed by missing
early sampling. Test across years/locations and retain the cinerosa case as a
guard against late-tail contamination. No serving-model or database changes were
made during this diagnosis.

### Local onset pilot and embedded gall chart

Implemented the requested evidence-weighted correction in a separate pure
`Phenology.Onset` module, without per-species files or climate downloads. One-degree
grid points use ±1° neighborhoods; earliest normalized development supplies the
local edge, and only the following fourteen days supply support. Count unique
quarter-degree locality/year combinations, cap support at two per year, subtract
one, and shrink with `s / (s + 2)`. Isolated local edges cannot force corrections.
Smooth, bounded interpolation retains the earliest anchor locally. Beyond the
supported region, continue the clock from the nearest corrected phase rather
than bending back to the original southern date. Distant support is warned about,
not displayed as a confidence probability. All constants are provisional pilot
heuristics, not ecological invariants.

Full-data DQP onset at 40°N is now April 11 (fallback April 2), and at 45°N May 8
(fallback April 13). Cinerosa at 30°N remains July 15. Cross-year and buffered
latitude-band tests improve against first-positive proxies for DQP, Eurosta,
quercusoperator sexual and quercushirta agamic. Cinerosa's three spatial holdouts
worsen (18.4 → 28.6 days mean absolute error), despite retaining the full-data
July anchor; this is not ready to claim universal validation. No parameters were
tuned on the held-out folds. Full curve generation measured roughly 1–23 ms for
the checked cohorts. The application snapshot has no developing records matching
eburne; this benchmark did not import data to fill that gap. Detailed read-only
audit scripts/results remain in Phenology/local-imports/release-review.

Gall pages now embed the same chart hook and shared point payload used by the
explorer, with a read-only selection mode so they do not mutate explorer brush
state. Observations and source totals appear on expansion before a latitude is
entered. Latitude entry adds the shared event lines and dates; the compact plot
includes the requested latitude, including extrapolation cases. Evidence/payload
loading remains lazy and cached. Source-count breakdown is restored. No old
stage-duration model or second rendering implementation was introduced.

Verification for this follow-up: `mix precommit` passes (2,213 tests, 84 standard
exclusions), Dialyzer reports zero errors, 184 JavaScript tests pass, and assets
build succeeds. The read-only real-data check retains all 36 emergence/rearing
comparisons. Edge browser checks cover compact chart before/after latitude entry,
desktop/mobile sizing, shared prediction arrays, absent brush controls on the
compact chart, source totals, and existing explorer toggle/panel independence.

### Broader correction and full-width compact chart

Adam found the one-degree local changes too lumpy and ecologically unsupported.
The correction now has knots spaced five degrees apart, centered on the earliest
anchor's latitude, with observations assigned to the nearest knot. Outer bands
include records through the supported domain edges. The same early-window support
and bounded interpolation rules remain; no changes to emergence or collections.
This is a scale constraint on the fitted correction, not cosmetic chart smoothing.

The broader DQP estimate is April 12 at 40°N and April 29 at 45°N; cinerosa at 30°N
remains July 15. The loss of the narrow northern May 8 fit is a visible tradeoff,
not concealed as unchanged timing. DQP buffered spatial holdout MAE is 5.0 days
(12.6 fallback; 5.5 narrow pilot), and year holdout MAE is 14.2 days (21.2 fallback;
13.9 narrow pilot). Eurosta improves versus fallback but less than with the narrow
pilot; cinerosa's three spatial holdouts still worsen versus fallback (18.4 →
20.0 days), though less than before. These are sampling-dependent first-positive
proxies. The five-degree scale was requested, not selected by holdout optimization.

The compact gall chart is now full-width, with latitude and results below it at
all breakpoints. Browser coverage includes 960px half-screen width as well as
desktop/mobile; the chart must fill its panel and the input must lie below it.

Verification: 2,215 Elixir tests pass with the 84 standard exclusions, assets build
passes, and the actual-browser layout/interaction checks pass. Regression tests
enforce five-degree minimum knot spacing, preservation of the source anchor,
domain-edge evidence inclusion, and the full-width gall layout. The 36 unchanged
emergence/rearing comparisons still match; no observation data was modified.

Release still requires maintainer acceptance and a separately reviewed, explicit
curated data batch with an import audit. A complete GF–iNat crosswalk and scheduled
imports are not prerequisites; unresolved identities must stay out of the batch.
The latitude-only reference is not locally validated weather, altitude or host
phenology. Keep regional refinement and broader product ideas separate.
