import { phenologyState, escapeHtml, readPoints, applySelection } from './phenology_state'

// Cap on how many rows we render in the DOM. Anything past this lives
// only in memory (and in the CSV download). Keeps the page from
// stretching to thousands-of-rows length when a wide brush picks up
// most of the obs set.
const OBS_ROW_CAP = 50
const SPECIES_ROW_CAP = 200

// Renders the data table or species list below the phenology chart from
// the same `data-points` array the chart and tooltip already consume.
//
// The host element is marked `phx-update="ignore"` — once we mount, the
// LV stops touching the inner DOM and the hook owns it. Re-render is
// driven by two things:
//
//   1. Brush changes (instant, no server roundtrip). The chart hook
//      pushes new bounds into `phenologyState`; we re-render rows.
//
//   2. The underlying obs set changing (filter applied → new
//      data-points on the chart). The LV bumps `data-version` on the
//      host, our `updated()` runs, we re-render from the latest points.
//
// This is the answer to "why is the table slow when the tooltip is
// instant?" — both now read from the same in-memory array; only the
// CSV link href + the brush counter still round-trip through the LV.

export default {
  mounted() {
    this._unsubscribe = phenologyState.subscribe(() => this.render())
    this._lastVersion = this.el.dataset.version || ''
    this._lastMode = this.el.dataset.mode || ''
    this._lastSort = this.el.dataset.sort || ''
    this.render()
  },

  updated() {
    // Host attribute changed — filter applied (new obs version), display mode
    // toggled (table ↔ species), or the species-list sort changed. Re-render.
    const v = this.el.dataset.version || ''
    const m = this.el.dataset.mode || ''
    const s = this.el.dataset.sort || ''
    if (v !== this._lastVersion || m !== this._lastMode || s !== this._lastSort) {
      this._lastVersion = v
      this._lastMode = m
      this._lastSort = s
      this.render()
    }
  },

  destroyed() {
    if (this._unsubscribe) this._unsubscribe()
  },

  render() {
    const points = readPoints()
    const filtered = applySelection(points)
    const mode = this.el.dataset.mode || 'table'

    if (mode === 'species') {
      this.el.innerHTML = renderSpeciesTable(filtered, this.el.dataset.sort || 'name')
    } else {
      this.el.innerHTML = renderObsTable(filtered)
    }
  },
}

// ---------------------------------------------------------------------
// Obs table
// ---------------------------------------------------------------------

const OBS_HEADERS = [
  'Species', 'Phenophase', 'Lifestage', 'Viability', 'Host',
  'DOY', 'Date', 'Lat', 'Lng', 'Source', 'Page',
]

function renderObsTable(points) {
  const total = points.length
  const shown = Math.min(total, OBS_ROW_CAP)
  const head = OBS_HEADERS.map((h) => `<th>${escapeHtml(h)}</th>`).join('')
  const body = points.slice(0, OBS_ROW_CAP).map(obsRow).join('')
  return `
    ${truncationNotice(shown, total, 'observations')}
    <table id="phenology-obs-table" class="gf-table gf-table-compact gf-table-zebra">
      <thead><tr>${head}</tr></thead>
      <tbody id="phenology-obs-table-body">${body}</tbody>
    </table>
  `
}

function truncationNotice(shown, total, noun) {
  if (total <= shown) return ''
  return (
    `<div style="padding: 6px 10px; font-size: 12px; color: #555; ` +
    `background: #f5f3ec; border-bottom: 1px solid #ddd;">` +
    `Showing ${shown} of ${total} ${noun}. Use the CSV download for the full set.` +
    `</div>`
  )
}

function obsRow(o) {
  return (
    '<tr>' +
    cell(o.species_name) +
    cell(orDash(o.phenophase)) +
    cell(orDash(o.lifestage)) +
    cell(orDash(o.viability)) +
    cell(orDash(o.host_species_name)) +
    cell(o.doy) +
    cell(o.date || '') +
    cell(formatCoord(o.lat)) +
    cell(formatCoord(o.lng)) +
    linkCell(o.source_url) +
    linkCell(o.page_url) +
    '</tr>'
  )
}

function cell(value) {
  return `<td>${escapeHtml(value)}</td>`
}

function linkCell(url) {
  if (!url) return '<td>—</td>'
  return `<td><a href="${escapeHtml(url)}" target="_blank" rel="noopener">link</a></td>`
}

function orDash(v) {
  return v == null || v === '' ? '—' : v
}

function formatCoord(c) {
  if (typeof c !== 'number') return ''
  return c.toFixed(3).replace(/\.?0+$/, '')
}

// ---------------------------------------------------------------------
// Species list (one row per species with obs count)
// ---------------------------------------------------------------------

function renderSpeciesTable(points, sort) {
  const groups = new Map()
  for (const p of points) {
    const g = groups.get(p.species_id)
    if (g) {
      g.n_obs += 1
      if (p.doy < g.doy_min) g.doy_min = p.doy
      if (p.doy > g.doy_max) g.doy_max = p.doy
      if (p.date && p.date > g.last_date) g.last_date = p.date
    } else {
      groups.set(p.species_id, {
        species_id: p.species_id,
        name: p.species_name,
        n_obs: 1,
        doy_min: p.doy,
        doy_max: p.doy,
        last_date: p.date || '',
      })
    }
  }

  const rows = Array.from(groups.values())
  for (const r of rows) r.spread = r.doy_max - r.doy_min
  sortSpeciesRows(rows, sort)

  const total = rows.length
  const shown = Math.min(total, SPECIES_ROW_CAP)
  const body = rows
    .slice(0, SPECIES_ROW_CAP)
    .map(
      (r) =>
        `<tr>
          <td><a href="/gall/${encodeURIComponent(r.species_id)}">${escapeHtml(r.name)}</a></td>
          <td>${r.n_obs}</td>
          <td>${r.spread}</td>
          <td>${escapeHtml(r.last_date || '—')}</td>
        </tr>`,
    )
    .join('')

  return `
    ${truncationNotice(shown, total, 'species')}
    <table id="phenology-species-table" class="gf-table gf-table-compact gf-table-zebra">
      <thead><tr><th>Species</th><th>Observations</th><th>DOY span</th><th>Latest</th></tr></thead>
      <tbody>${body}</tbody>
    </table>
  `
}

// Mirrors Phenology.sort_species_rows/2 (name is the stable tiebreaker).
function sortSpeciesRows(rows, sort) {
  const byName = (a, b) => (a.name || '').localeCompare(b.name || '')
  switch (sort) {
    case 'obs_count':
      rows.sort((a, b) => b.n_obs - a.n_obs || byName(a, b))
      break
    case 'spread':
      rows.sort((a, b) => b.spread - a.spread || byName(a, b))
      break
    case 'recency':
      rows.sort((a, b) => (b.last_date || '').localeCompare(a.last_date || '') || byName(a, b))
      break
    default:
      rows.sort(byName)
  }
}
