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
cell equal total weight. A weighted circular mean centers the year before
weighted quantiles are calculated. Fresh-gall onset shows q05–q10, not the duration
of developing galls. Emergence pools maturing and Free-living phases (not
perimature or enclosed Adult annotations). Viable collections require explicit
`viability == "viable"`, regardless of phenophase. Those events show q25–q75,
with q10–q90 and the median as context. Display filters never restrict event input.

These are descriptive fallback estimates, not confidence intervals, physiological
thresholds or a mechanistic lifecycle model. Sparse evidence and extrapolation
are labeled. A single site can supply event thresholds but does not validate the
latitude-transfer relationship. Multimodal cohorts may not be well summarized by
one window. The reference is eastern/central North American, not local weather;
altitude, aspect, host and annual variation are not modeled. Do not use its
latitude coverage as a claim of geographic validation elsewhere.

No automatic imports, taxonomic pairing, regional climate model, or perimature
review-queue heuristics are part of this application implementation.
