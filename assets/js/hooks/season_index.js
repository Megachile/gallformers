// Season-index math, a faithful port of Gallformers.Phenology.Math
// (season_index/2) so the client can compute a season index from a
// (day-of-year, latitude) pair without a server roundtrip. Kept in step
// with the Elixir version — the CSV export recomputes the same value
// server-side via Phenology.season_index/2, so the two must agree.
//
// Season index is the fraction of the year's total daylight hours that
// have accumulated by a given DOY at a given latitude (0 → 1). It lets a
// date be compared across latitudes: "the same point in the daylight
// year" rather than the same calendar date.

export function declination(doy) {
  return 23.45 * Math.sin((2 * Math.PI * (284 + doy)) / 365)
}

export function eq(doy, lat) {
  const latRad = (lat * Math.PI) / 180
  const declRad = (Math.PI * declination(doy)) / 180
  let arg = -Math.tan(latRad) * Math.tan(declRad)
  if (arg < -1) arg = -1
  if (arg > 1) arg = 1
  return 2 * (24 / (2 * Math.PI)) * Math.acos(arg) - (0.1 * lat + 5)
}

const pos = (x) => (x > 0 ? x : 0)

function trapzEqPos(start, end, lat) {
  if (end < start) return 0
  const hStart = pos(eq(start, lat))
  const hEnd = pos(eq(end, lat))
  let interior = 0
  for (let d = start + 1; d <= end - 1; d++) interior += pos(eq(d, lat))
  return (hStart + hEnd) / 2 + interior
}

export function seasonIndex(doy, lat) {
  let d = doy
  if (d < 1) d = 1
  if (d > 365) d = 365
  const numerator = trapzEqPos(1, d, lat)
  const denominator = trapzEqPos(1, 365, lat)
  return denominator === 0 ? 0 : numerator / denominator
}

// Cumulative season index at each DOY 1..365 for a latitude (index 0
// unused). Computing the whole profile once lets us invert it for several
// targets cheaply — used to draw the season-index selection band on the
// chart, where each latitude has its own DOY→seasind curve.
export function seasindProfile(lat) {
  const den = trapzEqPos(1, 365, lat) || 1
  const cum = new Float64Array(366)
  let c = 0
  let prevH = 0
  for (let d = 1; d <= 365; d++) {
    const h = pos(eq(d, lat))
    c += ((prevH + h) / 2) / den
    prevH = h
    cum[d] = c
  }
  return cum
}

// First DOY whose cumulative season index reaches `target`, given a profile
// from seasindProfile/1. Mirrors Gallformers.Phenology.Math.doy_for_seasind/2.
export function doyForSeasindFromProfile(cum, target) {
  if (target <= 0) return 1
  if (target >= 1) return 365
  for (let d = 1; d <= 365; d++) if (cum[d] >= target) return d
  return 365
}

// Day-of-year (1–365) for a JS Date, ignoring the year — matches the
// Shiny app's `format(date, "%j")`.
export function doyOf(date) {
  const start = Date.UTC(date.getUTCFullYear(), 0, 0)
  const diff = Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()) - start
  return Math.floor(diff / 86400000)
}
