# Seasonal landmark reference

`seasonal_landmarks.csv` is the fixed, species-independent latitude reference
used by `Gallformers.Phenology.SeasonalClock`. It is compiled into the module;
serving predictions requires neither climate downloads nor an R/Python process.

## Provenance

Generated in the September 2026 phenology pilot by
`benchmark_seasonal_onset.R` and `seasonal_landmark_clock.R` in
[Megachile/Phenology](https://github.com/Megachile/Phenology). Input: WorldClim 2.1
monthly mean-temperature normals, sampled at one-degree longitude intervals
from 100°W to 70°W and averaged over available land samples at each quarter-degree
latitude from 25°N through 55°N. The monthly series is interpolated periodically
to daily temperatures. Spring and autumn columns are the dates at which 10% and
90% of annual positive temperature exposure above 5°C have accumulated.
`warm_days` is their difference. These are thermal landmarks, not measurements
of host budbreak or leaf senescence.

## Calculation and scope

The warm interval maps to 0–182.5 clock units; autumn through the following spring
maps to 182.5–365. Both segments are linear, continuous, monotone and periodic.
Latitude interpolation is linear between adjacent grid rows. Inversion supplies
both the chart contours and the displayed dates. Dates use a fixed non-leap year;
February 29 maps to February 28.

The prediction layer pools selected species within generation. It collapses
replicate species/date/0.1°-locality records and gives each occupied 1° geographic
cell equal total weight. A weighted circular mean centers the year, keeping
December–January seasons together. Fresh-gall onset uses the earliest developing
record on that centered, latitude-normalized clock as a fallback, with the local
correction described below. It does not estimate the duration of developing
galls. Its single line/date links to the fallback anchor record
where a source URL is available. Query-order-independent deduplication makes that
anchor reproducible. This is an earliest **recorded** onset estimate: the input
has no separate verified-fresh flag, and an early mislabel can move the line.
It is not proof of the true first induction date or a confidence bound. Curate
the upstream stage label to correct it; there are no per-species overrides.
The circular centering still assumes a coherent season, not year-round or
several independent developing phases.

### Local onset correction pilot

`Phenology.Onset` adjusts the fallback where repeated local early records support
a different seasonal phase. Correction knots are now **five degrees apart**,
centered on the earliest record's latitude. Each record belongs to the nearest
supported knot, giving five-degree bands (the outer bands extend to the supported
domain boundaries). Take the earliest phase in each band. Only observations
within fourteen calendar days of that local edge
(all projected to the neighborhood's latitude) contribute support. Collapse
support to quarter-degree locality/year combinations, with at most two
contributions per year. Thus a hundred late photos or repeated photos from one
trip do not overwhelm an early record.

Let `s = max(0, min(locality_year_count, 2 * year_count) - 1)`. The node's
correction is `s / (s + 2) * (local_edge_phase - fallback_phase)`. Isolated local
edges do not create correction nodes. Neighborhoods containing the global
earliest phase remain zero-correction anchors. A bounded cubic smoothstep
interpolates the corrections between nodes without overshooting them. Gaps
between correction knots are always at least five degrees, so the model cannot
trace the one-degree fluctuations seen in the first local pilot. Neither
species-specific artifacts nor new climate downloads are needed.

Beyond supported nodes, continue the shared clock from the nearest **adjusted**
phase. Do not fade the correction back to the original distant anchor: doing so
created an artificial earlier turn north of the DQP observations. The local
evidence weight, not the date correction, declines to zero over four degrees
from support; weight below 0.2 triggers a plain-language fallback warning. This
weight is a disclosure heuristic, not a probability or calibrated confidence.

All neighborhoods, support rules and smoothing settings are fixed pilot choices,
not biological constants or learned parameters. Local first-positive dates can
still be late because of missing early sampling, and repeated old galls can
misrepresent a local early edge. A local correction does not imply a host,
elevation, longitude or annual climate adjustment. Curated onset anchors remain
important even in datasets with many developing records.

Read-only snapshot checks for the broader pilot: DQP onset at 40°N moves April 2
→ April 12, and at 45°N April 13 → April 29. Cinerosa at 30°N stays July 15.
Leaving whole years out reduces DQP mean absolute error against held-out
first-positive dates from 21.2 to 14.2 days; buffered latitude-band holdouts reduce
it from 12.6 to 5.0 days. Eurosta also improves (24.0 → 20.8 and 17.1 → 13.6 days).
Cinerosa latitude-band holdouts **worsen** (18.4 → 20.0 days, only three folds).
These sampling-dependent first
records are not true-onset labels or observed absences. This supports a preview,
not a claim of universal model validation. The five-degree scale follows the
requested broader ecological effect, not an optimization on these folds. Compared
with the narrow pilot, some held-out scores improve and others deteriorate.

### Other events and presentation

The gall-page chart spans the full panel width at every viewport size. Its
latitude input and shared date summary sit below it, rather than taking half
the available plot width. The chart remains lazy-loaded and uses the explorer's
plotting code in read-only selection mode.

Emergence pools maturing and Free-living phases (not
perimature or enclosed Adult annotations). Viable collections require explicit
`viability == "viable"`, regardless of phenophase. Those events show q25–q75,
with q10–q90 and the median as context. Display filters never restrict event input.

These are descriptive fallback estimates, not confidence intervals, physiological
thresholds or a mechanistic lifecycle model. Sparse evidence and extrapolation
are labeled in plain language, without exposing geographic-cell counts. Fewer
than five deduplicated records trigger a few-records warning. Outside the
observed latitude range, the requested and recorded latitudes are displayed as
an explicit extrapolation warning. Within that range, a span under two degrees
triggers a limited-latitude-coverage warning. These are disclosure heuristics,
not calibrated confidence scores; broad latitude coverage alone does not imply
good sampling throughout the range or longitude coverage.
A single site can supply event thresholds but does not validate the
latitude-transfer relationship. Multimodal cohorts may not be well summarized by
one window. The reference is eastern/central North American, not local weather;
altitude, aspect, host and annual variation are not modeled. Do not use its
latitude coverage as a claim of geographic validation elsewhere.

No automatic imports, taxonomic pairing, regional climate model, or perimature
review-queue heuristics are part of this application implementation.
