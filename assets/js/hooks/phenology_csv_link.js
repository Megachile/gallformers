import { phenologyState } from './phenology_state'

// Mounted on the `Download CSV` link. The link is server-rendered (its
// existence depends on display mode + obs presence) but its href needs
// to pick up brush bounds without an LV roundtrip.
//
// On every mount/update we re-read the base href from `data-href-base`
// (the server's URL without brush params) and append the current brush
// bounds, if any. We also subscribe to `phenologyState` so brush
// gestures update the href synchronously.

export default {
  mounted() {
    this._unsubscribe = phenologyState.subscribe(() => this.applyBrush())
    this.applyBrush()
  },

  updated() {
    // Server re-rendered the link (filter changed → new base href).
    // Re-apply brush on top of the fresh base.
    this.applyBrush()
  },

  destroyed() {
    if (this._unsubscribe) this._unsubscribe()
  },

  applyBrush() {
    const base = this.el.dataset.hrefBase || this.el.getAttribute('href') || ''
    const brush = phenologyState.brush
    const range = phenologyState.range
    const params = new URLSearchParams()

    if (brush) {
      params.set('doy_min', String(brush.doy_min))
      params.set('doy_max', String(brush.doy_max))
      params.set('lat_min', String(brush.lat_min))
      params.set('lat_max', String(brush.lat_max))
    }

    if (range) {
      // Distinct param names from the brush so the two lenses can't clash.
      for (const key of ['doy_min', 'doy_max', 'seasind_min', 'seasind_max']) {
        if (range[key] != null) params.set(`sel_${key}`, String(range[key]))
      }
    }

    const qs = params.toString()
    if (!qs) {
      this.el.href = base
      return
    }
    const sep = base.includes('?') ? '&' : '?'
    this.el.href = base + sep + qs
  },
}
