import { select } from 'd3-selection'
import { scaleLinear } from 'd3-scale'
import { axisBottom, axisLeft } from 'd3-axis'
import { extent } from 'd3-array'
import { brush } from 'd3-brush'
import { symbol, symbolCircle, symbolTriangle, symbolSquare,
         symbolStar, symbolCross, symbolDiamond, symbolWye } from 'd3-shape'
import { phenologyState } from './phenology_state'

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
  },

  destroyed() {
    if (this._clearBrushListener) {
      document.removeEventListener('phenology:clear-brush', this._clearBrushListener)
    }
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
    if (points.length === 0) {
      select(this.el).append('div')
        .style('padding', '40px')
        .style('text-align', 'center')
        .style('color', '#888')
        .text('No observations to display.')
      return
    }

    const margin = { top: 20, right: 20, bottom: 50, left: 56 }
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
  }
}

function escapeHtml(s) {
  return String(s == null ? '' : s).replace(/[&<>"']/g,
    c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c])
}
