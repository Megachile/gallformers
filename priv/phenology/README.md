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
record on that centered, latitude-normalized clock, not a percentile or the
duration of developing galls. Its single line/date links to the anchor record
where a source URL is available. Query-order-independent deduplication makes that
anchor reproducible. This is an earliest **recorded** onset estimate: the input
has no separate verified-fresh flag, and an early mislabel can move the line.
It is not proof of the true first induction date or a confidence bound. Curate
the upstream stage label to correct it; there are no per-species overrides.
The circular centering still assumes a coherent season, not year-round or
several independent developing phases.

### Retired local-onset pilot

The local evidence correction was withdrawn on September 7, 2026. Its code,
parameters, benchmark results and limitations are recorded in Mull matter 439a,
with a separate replayable local archive. The narrow pilot is recoverable at
commit `7098247e`; the broader five-degree pilot at `e98e05dc`.

Neither correction is part of the serving model. Repeated local first-positive
dates can reflect late sampling of persistent galls rather than local onset.
Smoothing those dates did not resolve that ambiguity and produced implausibly
late southern cinerosa estimates. The restored shared-clock curve accepts its
known latitude-transfer limitations, including early northern DQP predictions,
without learning a species-specific curve from those local dates.

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
