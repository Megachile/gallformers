// Tiny module-scoped pub/sub so the chart hook can push brush bounds at
// the table hook without going back through the LV. The chart owns the
// gesture; the table mirrors it. Both also receive identical bounds via
// the server's set_selection round-trip (for CSV link + counter), so
// this is purely the fast-path used to skip the server roundtrip for
// the visible table update.

const listeners = new Set()

export const phenologyState = {
  // Current brush bounds in data domain: {doy_min, doy_max, lat_min, lat_max}
  // or null when no brush is active.
  brush: null,

  setBrush(b) {
    this.brush = b
    listeners.forEach((fn) => fn())
  },

  // Returns an unsubscribe function. Callers (e.g. the table hook) call it
  // from their `destroyed` lifecycle so we don't accumulate dead listeners
  // across LV navigations.
  subscribe(fn) {
    listeners.add(fn)
    return () => listeners.delete(fn)
  },
}

// Read the obs array off the chart hook's data-points attribute. All
// chrome/table hooks render from this same in-memory array — same data
// the tooltip uses, which is why their updates feel instant.
export function readPoints() {
  const chartEl = document.getElementById('phenology-chart')
  if (!chartEl) return []
  try {
    return JSON.parse(chartEl.dataset.points || '[]')
  } catch (e) {
    return []
  }
}

// Pure JS brush filter — kept in step with the server's apply_brush in
// the CSV controller so the downloaded file matches what's on screen.
export function applyBrush(points, brush) {
  if (!brush) return points
  const { doy_min, doy_max, lat_min, lat_max } = brush
  return points.filter(
    (p) =>
      p.doy >= doy_min &&
      p.doy <= doy_max &&
      typeof p.lat === 'number' &&
      p.lat >= lat_min &&
      p.lat <= lat_max,
  )
}

// HTML escape for any user-controlled or external-API string interpolated
// into innerHTML.
export function escapeHtml(s) {
  return String(s == null ? '' : s).replace(/[&<>"']/g,
    (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c])
}
