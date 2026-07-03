import { phenologyState } from './phenology_state'

// Explicit day-of-year / season-index range inputs that act as a
// display-only selection lens on the table / species list / CSV — the
// same thing the chart brush does, but typed and able to constrain
// season index (which isn't a chart axis). Purely client state; it
// publishes to phenologyState.range and never round-trips the LV.
//
// The host is `phx-update="ignore"` so LiveView re-renders don't wipe the
// typed values. Each input carries a `data-range="doy_min|doy_max|
// seasind_min|seasind_max"` marker the hook reads.

export default {
  mounted() {
    this._onInput = () => this.publish()
    this.el.addEventListener('input', this._onInput)

    const clear = this.el.querySelector('[data-range-clear]')
    if (clear) {
      this._onClear = () => {
        this.el.querySelectorAll('input[data-range]').forEach((el) => {
          el.value = ''
        })
        this.publish()
      }
      clear.addEventListener('click', this._onClear)
      this._clearEl = clear
    }

    this.publish()
  },

  destroyed() {
    this.el.removeEventListener('input', this._onInput)
    if (this._clearEl && this._onClear) {
      this._clearEl.removeEventListener('click', this._onClear)
    }
  },

  publish() {
    const read = (name) => {
      const el = this.el.querySelector(`input[data-range="${name}"]`)
      if (!el || el.value === '') return null
      const n = parseFloat(el.value)
      return Number.isNaN(n) ? null : n
    }

    const range = {
      doy_min: read('doy_min'),
      doy_max: read('doy_max'),
      seasind_min: read('seasind_min'),
      seasind_max: read('seasind_max'),
    }

    const active = Object.values(range).some((v) => v != null)
    phenologyState.setRange(active ? range : null)

    const clear = this._clearEl
    if (clear) clear.style.display = active ? '' : 'none'
  },
}
