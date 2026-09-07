import { phenologyState } from './phenology_state'
import { seasonIndex, doyOf } from './season_index'

// Owns the "Selection mode" controls beneath the chart, a port of the
// legacy doyCalc selection modes:
//   • Click & drag  → the chart brush drives the selection (no inputs here)
//   • Date range    → a center date ± N days (circular DOY window)
//   • Season index  → a date + latitude + tolerance; we compute the season
//                     index here (season_index.js) and select a circular
//                     seasind band, so no one has to type a raw seasind.
//
// The modes are mutually exclusive. On any input the hook recomputes the
// selection and publishes it to phenologyState; the table / species list /
// CSV link all filter through phenologyState.applySelection. This is a
// display-only lens — it never touches the prediction windows.
//
// Host is phx-update="ignore" so typed values survive LV re-renders; the
// hook manages show/hide of the per-mode input groups itself.

export default {
  mounted() {
    this._onChange = () => this.publish()
    this.el.addEventListener('input', this._onChange)
    this.el.addEventListener('change', this._onChange)
    this.publish()
  },

  destroyed() {
    this.el.removeEventListener('input', this._onChange)
    this.el.removeEventListener('change', this._onChange)
    // Leaving the DOM (e.g. switching to predictions mode): drop any lens
    // so a later remount starts clean.
    phenologyState.setSelection({ mode: 'click_drag' })
  },

  currentMode() {
    const checked = this.el.querySelector('input[name="phenology-sel-mode"]:checked')
    return checked ? checked.value : 'click_drag'
  },

  readNum(sel) {
    const el = this.el.querySelector(`[data-sel="${sel}"]`)
    if (!el || el.value === '') return null
    const n = parseFloat(el.value)
    return Number.isNaN(n) ? null : n
  },

  readDoy() {
    const el = this.el.querySelector('[data-sel="date"]')
    if (!el || !el.value) return null
    const d = new Date(el.value + 'T00:00:00Z')
    if (Number.isNaN(d.getTime())) return null
    return doyOf(d)
  },

  // Show only the input groups relevant to the active mode. A group can
  // belong to several modes (space-separated), e.g. the shared date input.
  syncGroups(mode) {
    this.el.querySelectorAll('[data-sel-group]').forEach((g) => {
      const modes = g.dataset.selGroup.split(' ')
      g.classList.toggle('hidden', !modes.includes(mode))
    })
  },

  publish() {
    const mode = this.currentMode()
    this.syncGroups(mode)

    if (mode === 'date_range') {
      phenologyState.setSelection({
        mode: 'date_range',
        doy: this.readDoy(),
        days: this.readNum('days'),
      })
    } else if (mode === 'season_index') {
      const doy = this.readDoy()
      const lat = this.readNum('lat')
      const thr = this.readNum('thr')
      const si = doy != null && lat != null ? seasonIndex(doy, lat) : null
      // doy/lat kept on the object so the CSV link can send them to the
      // server, which recomputes si identically.
      phenologyState.setSelection({ mode: 'season_index', si, thr, doy, lat })
    } else {
      phenologyState.setSelection({ mode: 'click_drag' })
    }
  },
}
