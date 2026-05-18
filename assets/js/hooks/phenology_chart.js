import { select } from 'd3-selection'
import { scaleLinear } from 'd3-scale'
import { axisBottom, axisLeft } from 'd3-axis'
import { extent } from 'd3-array'
import { symbol, symbolCircle, symbolTriangle, symbolSquare,
         symbolStar, symbolCross, symbolDiamond, symbolWye } from 'd3-shape'

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
  mounted()  { this.renderChart() },
  updated()  { this.renderChart() },

  renderChart() {
    const points = JSON.parse(this.el.dataset.points || '[]')

    select(this.el).selectAll('*').remove()
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

    // Points — color per-point by generation (multi-species safe; pre-multi-
    // species the LV passed a single generation via data-generation, but
    // each point now carries its own).
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
