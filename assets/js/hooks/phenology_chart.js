import { select } from 'd3-selection'
import { scaleLinear } from 'd3-scale'
import { axisBottom, axisLeft } from 'd3-axis'
import { extent } from 'd3-array'
import { brush } from 'd3-brush'
import { symbol, symbolCircle, symbolTriangle, symbolSquare,
         symbolStar, symbolCross, symbolDiamond, symbolWye } from 'd3-shape'
import { phenologyState } from './phenology_state'
import { seasindProfile, doyForSeasindFromProfile } from './season_index'

// Mapping must match `Gallformers.Phenology.Observation.phenophases/0`.
const PHENO_SYMBOL = {
  'developing':  symbolCircle,
  'maturing':    symbolTriangle,
  'dormant':     symbolSquare,
  'perimature':  symbolCross,
  'oviscar':     symbolStar,
  'senescent':   symbolWye,
  'Free-living': symbolDiamond,
}

const GEN_COLOR = {
  'sexgen':  '#1f77b4',
  'agamic':  '#d62728',
  'unknown': '#555555',
}

// Human-readable legend labels for the encodings above.
const GEN_LABEL = {
  'sexgen':  'Sexual',
  'agamic':  'Agamic',
  'unknown': 'Unknown',
}

const PHENO_LABEL = {
  'developing':  'Developing',
  'maturing':    'Maturing',
  'dormant':     'Dormant',
  'perimature':  'Recently emerged',
  'oviscar':     'Oviposition scar',
  'senescent':   'Senescent',
  'Free-living': 'Free-living',
}

const MONTH_TICKS  = [1, 32, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335]
const MONTH_LABELS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec']

export default {
  mounted() {
    this.renderChart()
    // The chrome hook's Clear-selection button dispatches this event when
    // clicked. We clear the SVG rect (the moveBrush('') below uses the
    // restoringBrush flag so the d3 end handler doesn't echo) and then
    // explicitly publish the cleared state so the table + chrome
    // subscribers update.
    this._clearBrushListener = () => {
      if (this._moveBrush) this._moveBrush('')
      phenologyState.setBrush(null)
    }
    document.addEventListener('phenology:clear-brush', this._clearBrushListener)

    // Redraw the Date-range / Season-index selection overlay whenever the
    // selection changes (the select hook publishes on every input). The
    // brush's own rectangle is drawn by d3-brush, so click_drag mode draws
    // no custom overlay.
    this._selectionUnsub = phenologyState.subscribe(() => this.drawSelectionOverlay())
  },

  destroyed() {
    if (this._clearBrushListener) {
      document.removeEventListener('phenology:clear-brush', this._clearBrushListener)
    }
    if (this._selectionUnsub) this._selectionUnsub()
  },

  // Only point-set changes drive a chart rebuild now. The brush state
  // lives entirely in `phenologyState` and the JS hooks — no server
  // roundtrip on brush gestures.
  updated() {
    const pointsRaw = this.el.dataset.points || '[]'
    if (pointsRaw !== this._lastPointsRaw) {
      this.renderChart()
    }
  },

  renderChart() {
    const pointsRaw = this.el.dataset.points || '[]'
    const points = JSON.parse(pointsRaw)
    this._lastPointsRaw = pointsRaw

    // A full chart rebuild only happens on initial mount or when the
    // underlying obs set changed (filter applied). The LV wipes its
    // server-side selection on filter changes, so any prior client-side
    // brush is no longer meaningful — drop it so the table hook re-renders
    // the new full set.
    phenologyState.setBrush(null)

    select(this.el).selectAll('*').remove()
    this._moveBrush = null
    // Scales/overlay from a previous render are gone now; null them so the
    // selection subscriber (which can fire mid-rebuild via setBrush below)
    // skips until we rebuild them.
    this._x = null
    this._y = null
    this._overlayG = null
    if (points.length === 0) {
      select(this.el).append('div')
        .style('padding', '40px')
        .style('text-align', 'center')
        .style('color', '#888')
        .text('No observations to display.')
      return
    }

    // Right margin holds the generation/phenophase legend.
    const margin = { top: 20, right: 150, bottom: 50, left: 56 }
    const width  = this.el.clientWidth  - margin.left - margin.right
    const height = this.el.clientHeight - margin.top  - margin.bottom

    const svg = select(this.el)
      .append('svg')
        .attr('width',  width + margin.left + margin.right)
        .attr('height', height + margin.top  + margin.bottom)
      .append('g')
        .attr('transform', `translate(${margin.left},${margin.top})`)

    // Tooltip (singleton, attached to body for z-index sanity)
    const tooltip = select('body').selectAll('.phenology-tooltip').data([null])
      .join('div')
        .attr('class', 'phenology-tooltip')
        .style('position', 'absolute')
        .style('visibility', 'hidden')
        .style('background', 'rgba(0, 0, 0, 0.85)')
        .style('color', '#fff')
        .style('padding', '6px 10px')
        .style('border-radius', '4px')
        .style('font-size', '12px')
        .style('line-height', '1.4')
        .style('pointer-events', 'none')
        .style('z-index', '1000')

    const x = scaleLinear().domain([-5, 371]).range([0, width])
    const latExtent = extent(points, d => d.lat)
    const latPad = Math.max(1, (latExtent[1] - latExtent[0]) * 0.05)
    const y = scaleLinear().domain([latExtent[0] - latPad, latExtent[1] + latPad]).nice().range([height, 0])

    // Axes
    svg.append('g')
      .attr('transform', `translate(0,${height})`)
      .call(axisBottom(x).tickValues(MONTH_TICKS).tickFormat((_, i) => MONTH_LABELS[i]))

    svg.append('g').call(axisLeft(y).ticks(6))

    svg.append('text')
      .attr('x', width / 2).attr('y', height + margin.bottom - 8)
      .attr('text-anchor', 'middle').style('font-size', '12px').style('fill', '#666')
      .text('Day of year')

    svg.append('text')
      .attr('transform', 'rotate(-90)')
      .attr('x', -height / 2).attr('y', -margin.left + 16)
      .attr('text-anchor', 'middle').style('font-size', '12px').style('fill', '#666')
      .text('Latitude (°N)')

    // Brush layer — added BEFORE the points so points stay above and can
    // receive mouseover events for tooltips. d3-brush emits an "end" event
    // on mouseup; we translate the pixel selection back to data domain
    // and publish to `phenologyState`. Table + chrome hooks subscribe.
    // The chart-side moveBrush below uses `restoringBrush` to suppress the
    // d3 "end" event that fires when we programmatically clear the rect.
    let restoringBrush = false
    const chartBrush = brush()
      .extent([[0, 0], [width, height]])
      .on('end', ({ selection }) => {
        if (restoringBrush) return
        if (!selection) {
          phenologyState.setBrush(null)
          return
        }
        const [[x0, y0], [x1, y1]] = selection
        const bounds = {
          doy_min: Math.floor(x.invert(x0)),
          doy_max: Math.ceil(x.invert(x1)),
          // y axis is inverted in screen space — top pixel is highest lat,
          // so we take the min/max explicitly to stay generation-agnostic.
          lat_min: Math.min(y.invert(y0), y.invert(y1)),
          lat_max: Math.max(y.invert(y0), y.invert(y1)),
        }
        phenologyState.setBrush(bounds)
      })

    const brushG = svg.append('g')
      .attr('class', 'brush')
      .call(chartBrush)

    // Selection overlay for the Date-range / Season-index modes, drawn above
    // the brush background but below the points (so points stay visible on
    // the shading). pointer-events none so it never eats point hovers or
    // brush drags. Populated by drawSelectionOverlay().
    this._x = x
    this._y = y
    this._width = width
    this._height = height
    this._brushG = brushG
    this._overlayG = svg.append('g')
      .attr('class', 'selection-overlay')
      .attr('pointer-events', 'none')

    // Programmatically clear the rectangle (called from the chrome's
    // Clear-selection listener). `restoringBrush` suppresses the d3 "end"
    // event the move below would otherwise emit.
    const moveBrush = (_raw) => {
      restoringBrush = true
      try {
        brushG.call(chartBrush.move, null)
      } catch (e) {
        // Defensive — leave the brush untouched.
      }
      restoringBrush = false
    }
    this._moveBrush = moveBrush

    // Points — drawn on top of the brush overlay. Each path captures its
    // own mouseover; the brush still works for empty-area drag-selection.
    const symbolGen = symbol().size(60)
    svg.selectAll('path.obs')
      .data(points).enter()
      .append('path')
        .attr('class', 'obs')
        .attr('d', d => symbolGen.type(PHENO_SYMBOL[d.phenophase] || symbolCircle)())
        .attr('transform', d => `translate(${x(d.doy)},${y(d.lat)})`)
        .attr('fill', d => GEN_COLOR[d.generation] || GEN_COLOR.unknown)
        .attr('fill-opacity', 0.55)
        .attr('stroke', '#222')
        .attr('stroke-width', 0.4)
        .style('cursor', 'pointer')
        .style('pointer-events', 'all')
        .on('mouseover', function (event, d) {
          select(this).attr('fill-opacity', 1)
          const speciesLine = d.species_name
            ? `<b>${escapeHtml(d.species_name)}</b><br>`
            : ''
          tooltip.style('visibility', 'visible')
            .html(`${speciesLine}<b>${escapeHtml(d.date)}</b>
                   <br>DOY ${d.doy} · lat ${d.lat.toFixed(2)}
                   <br>phenophase: ${escapeHtml(d.phenophase)}
                   <br>lifestage: ${escapeHtml(d.lifestage || '—')}
                   <br>viability: ${escapeHtml(d.viability || '—')}
                   <br>${escapeHtml([d.site, d.state, d.country].filter(Boolean).join(', ') || '—')}
                   <br><i>${escapeHtml(d.source_type)}</i>`)
        })
        .on('mousemove', function (event) {
          tooltip.style('top',  (event.pageY - 12) + 'px')
                 .style('left', (event.pageX + 12) + 'px')
        })
        .on('mouseout', function () {
          select(this).attr('fill-opacity', 0.55)
          tooltip.style('visibility', 'hidden')
        })

    // Legend in the right margin — color = generation, shape = phenophase.
    // Built only from the values actually present so it never lists an
    // encoding the current points don't use.
    this.drawLegend(svg, points, width)

    // Reflect the current selection (e.g. after a filter-driven rebuild the
    // user may already have a Date-range / Season-index lens active).
    this.drawSelectionOverlay()
  },

  // Draw the Date-range (vertical band) or Season-index (curved seasind
  // band) selection onto the chart, matching what applySelection filters in
  // the table. Cleared and redrawn on every selection change. click_drag
  // draws nothing here — d3-brush renders its own rectangle.
  drawSelectionOverlay() {
    const g = this._overlayG
    const x = this._x
    const y = this._y
    if (!g || !x || !y) return

    const sel = phenologyState.selection || { mode: 'click_drag' }

    // Hide the brush rectangle in the non-brush modes without clearing it, so
    // it (and its d3-brush selection) reappears in place on returning to
    // Click & drag. display:none also disables brushing in those modes.
    if (this._brushG) this._brushG.style('display', sel.mode === 'click_drag' ? null : 'none')

    g.selectAll('*').remove()
    const h = this._height
    const GREEN = '#2e7d32'

    const band = (x0, x1) =>
      g.append('rect')
        .attr('x', x0).attr('y', 0)
        .attr('width', Math.max(0, x1 - x0)).attr('height', h)
        .attr('fill', GREEN).attr('fill-opacity', 0.12)

    const vline = (px) =>
      g.append('line')
        .attr('x1', px).attr('y1', 0).attr('x2', px).attr('y2', h)
        .attr('stroke', GREEN).attr('stroke-width', 1).attr('stroke-dasharray', '4 3')

    if (sel.mode === 'date_range') {
      if (sel.doy == null || sel.days == null) return
      const lo = mod365(sel.doy - sel.days)
      const hi = mod365(sel.doy + sel.days)
      // A window that wraps the new year becomes two bands.
      const bands = lo <= hi ? [[lo, hi]] : [[0, hi], [lo, 365]]
      bands.forEach(([a, b]) => band(x(a), x(b)))
      ;[lo, hi].forEach((d) => vline(x(d)))
    } else if (sel.mode === 'season_index') {
      if (sel.si == null || sel.thr == null) return

      // Each latitude has its own DOY→seasind curve, so the band's edges bow
      // with latitude — precompute a seasind profile per sampled latitude.
      const [latMin, latMax] = y.domain()
      const N = 40
      const samples = []
      for (let i = 0; i <= N; i++) {
        const lat = latMin + ((latMax - latMin) * i) / N
        samples.push({ lat, cum: seasindProfile(lat) })
      }

      // The DOY-space isopleth for a seasind value, across latitudes.
      const isopleth = (s) =>
        samples.map((sm) => [x(doyForSeasindFromProfile(sm.cum, s)), y(sm.lat)])

      const fillBetween = (a, b) => {
        const left = isopleth(a)
        const right = isopleth(b)
        const poly = left.concat(right.slice().reverse())
        g.append('polygon')
          .attr('points', poly.map((p) => p.join(',')).join(' '))
          .attr('fill', GREEN).attr('fill-opacity', 0.12)
      }

      const edge = (s) =>
        g.append('path').attr('d', toPath(isopleth(s)))
          .attr('fill', 'none').attr('stroke', GREEN).attr('stroke-width', 1)
          .attr('stroke-dasharray', '4 3')

      // Season index is circular: the table filters on mod-distance, so a
      // band whose reference sits near the year boundary spills past seasind
      // 1 back to 0 (late December AND early January are one day apart). Mirror
      // that here — when [si−thr, si+thr] crosses 0 or 1, draw two bands split
      // at the year end, and dash only the two real selection edges (not the
      // Jan-1 / Dec-31 plot edges).
      const loRaw = sel.si - sel.thr
      const hiRaw = sel.si + sel.thr
      if (loRaw >= 0 && hiRaw <= 1) {
        fillBetween(loRaw, hiRaw)
      } else {
        const lo = mod1(loRaw)
        const hi = mod1(hiRaw)
        fillBetween(lo, 1)
        fillBetween(0, hi)
      }
      edge(mod1(loRaw))
      edge(mod1(hiRaw))
    }
    // click_drag: nothing — the brush draws its own rectangle.
  },

  drawLegend(svg, points, width) {
    const legendX = width + 16
    const legendSymbol = symbol().size(70)
    const legend = svg.append('g').attr('class', 'legend')
    let ly = 4

    const heading = (text) => {
      legend.append('text')
        .attr('x', legendX).attr('y', ly).attr('dominant-baseline', 'hanging')
        .style('font-size', '11px').style('font-weight', '600').style('fill', '#444')
        .text(text)
      ly += 18
    }

    const row = (type, fill, label) => {
      legend.append('path')
        .attr('d', legendSymbol.type(type)())
        .attr('transform', `translate(${legendX + 6},${ly + 3})`)
        .attr('fill', fill).attr('fill-opacity', 0.7)
        .attr('stroke', '#222').attr('stroke-width', 0.4)
      legend.append('text')
        .attr('x', legendX + 20).attr('y', ly + 3).attr('dominant-baseline', 'middle')
        .style('font-size', '11px').style('fill', '#444')
        .text(label)
      ly += 18
    }

    const gens = Object.keys(GEN_COLOR)
      .filter((g) => points.some((d) => (d.generation || 'unknown') === g))
    if (gens.length) {
      heading('Generation')
      gens.forEach((g) => row(symbolCircle, GEN_COLOR[g], GEN_LABEL[g] || g))
      ly += 8
    }

    const phenos = Object.keys(PHENO_SYMBOL)
      .filter((p) => points.some((d) => d.phenophase === p))
    if (phenos.length) {
      heading('Phenophase')
      phenos.forEach((p) => row(PHENO_SYMBOL[p], '#777', PHENO_LABEL[p] || p))
    }
  }
}

function escapeHtml(s) {
  return String(s == null ? '' : s).replace(/[&<>"']/g,
    c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c])
}

function mod365(v) {
  return ((v % 365) + 365) % 365
}

function mod1(v) {
  return ((v % 1) + 1) % 1
}

function toPath(points) {
  return points.map((p, i) => `${i === 0 ? 'M' : 'L'}${p[0]},${p[1]}`).join(' ')
}
