import { describe, test, expect } from 'vitest'
import { select } from 'd3-selection'
import { scaleLinear } from 'd3-scale'
import Chart from './phenology_chart'
import { phenologyState } from './phenology_state'

function render(prediction) {
  const el = document.createElement('div')
  el.dataset.predictions = JSON.stringify([prediction])
  const svg = select(el).append('svg')
  const hook = {
    el, _predictionG: svg.append('g'), _predictionLinesG: svg.append('g'),
    _predictionLabelsG: svg.append('g'),
    _x: scaleLinear().domain([0, 365]).range([0, 365]),
    _y: scaleLinear().domain([30, 40]).range([100, 0]), _width: 365
  }
  Chart.drawPredictions.call(hook)
  return el
}

describe('phenology prediction semantics', () => {
  test('both views use identical muted points and foreground interval lines without hiding records', () => {
    const styles = []
    for (const selectionEnabled of ['true', 'false']) {
      const el = document.createElement('div')
      Object.defineProperties(el, {clientWidth: {value: 800}, clientHeight: {value: 540}})
      el.dataset.selectionEnabled = selectionEnabled
      el.dataset.points = JSON.stringify(Array.from({length: 500}, (_, i) => ({
        lat: 35 + i / 1000, doy: 150, generation: 'sexgen', phenophase: 'developing'
      })))
      const rows = [35, 35.5].map(lat => ({lat, low_doy: 145, high_doy: 155,
        outer_low_doy: 140, outer_high_doy: 160, median_doy: 150}))
      el.dataset.predictions = JSON.stringify([{event: 'emergence', generation: 'sexgen',
        target_lat: 35.25, low_doy: 145, high_doy: 155, contours: rows}])
      const hook = {...Chart, el}
      hook.renderChart()
      const points = [...el.querySelectorAll('.obs')]
      expect(points).toHaveLength(500)
      const point = points[0]
      styles.push(['d', 'fill-opacity', 'stroke-opacity', 'stroke-width']
        .map(attr => point.getAttribute(attr)))
      expect(point.getAttribute('fill-opacity')).toBe('0.25')
      expect(point.getAttribute('stroke-opacity')).toBe('0.25')
      const parent = point.parentNode
      const children = [...parent.children]
      expect(children.indexOf(el.querySelector('.prediction-overlay'))).toBeLessThan(children.indexOf(point))
      expect(children.indexOf(el.querySelector('.prediction-lines'))).toBeGreaterThan(children.indexOf(points.at(-1)))
      expect(el.querySelector('.prediction-lines').getAttribute('pointer-events')).toBe('none')
      expect(el.querySelector('.prediction-lines').getAttribute('clip-path'))
        .toBe(el.querySelector('.prediction-overlay').getAttribute('clip-path'))
      expect(el.querySelectorAll('.prediction-boundary-halo')).toHaveLength(2)
      const edge = el.querySelector('.prediction-boundary')
      const halo = el.querySelector('.prediction-boundary-halo')
      expect(halo.getAttribute('stroke')).toBe('white')
      expect(halo.getAttribute('stroke-dasharray')).toBe(edge.getAttribute('stroke-dasharray'))

      point.dispatchEvent(new MouseEvent('mouseover', {bubbles: true}))
      expect(point.getAttribute('fill-opacity')).toBe('1')
      expect(point.getAttribute('stroke-opacity')).toBe('1')
      expect(document.querySelector('.phenology-tooltip').style.visibility).toBe('visible')
      point.dispatchEvent(new MouseEvent('mouseout', {bubbles: true}))
      expect(point.getAttribute('fill-opacity')).toBe('0.25')
      expect(point.getAttribute('stroke-opacity')).toBe('0.25')

      expect(document.querySelector('.phenology-tooltip').style.display).toBe('none')

      el.dataset.predictions = '[]'
      hook.drawPredictions()
      expect(el.querySelectorAll('.prediction-boundary, .prediction-boundary-halo, .prediction-median')).toHaveLength(0)
      expect(el.querySelectorAll('.obs')).toHaveLength(500)
      hook.destroyed()
    }
    expect(styles[0]).toEqual(styles[1])
  })

  test('compact chart has no brush, preserves explorer selection, and includes the target latitude', () => {
    const el = document.createElement('div')
    Object.defineProperties(el, {clientWidth: {value: 550}, clientHeight: {value: 420}})
    el.dataset.selectionEnabled = 'false'
    el.dataset.points = JSON.stringify([
      {lat: 35, doy: 140, generation: 'sexgen', phenophase: 'developing'},
      {lat: null, doy: 150, phenophase: 'developing'}])
    el.dataset.predictions = JSON.stringify([{event: 'onset', generation: 'sexgen', target_lat: 45,
      low_doy: 150, high_doy: 150,
      contours: [{lat: 35, low_doy: 140, high_doy: 140}, {lat: 45, low_doy: 150, high_doy: 150}]}])
    const selected = {doy_min: 100, doy_max: 200, lat_min: 30, lat_max: 40}
    phenologyState.setBrush(selected)
    const hook = {...Chart, el}
    hook.renderChart()
    expect(el.querySelectorAll('.brush')).toHaveLength(0)
    expect(el.querySelectorAll('.obs')).toHaveLength(1)
    expect(el.querySelectorAll('.prediction-date-marker')).toHaveLength(1)
    expect(phenologyState.brush).toEqual(selected)
    expect(hook._y.domain()[1]).toBeGreaterThan(45)
    hook.destroyed()
    phenologyState.setBrush(null)
  })

  test('compact chart with no plottable coordinates reports no observations', () => {
    const el = document.createElement('div')
    el.dataset.selectionEnabled = 'false'
    el.dataset.points = JSON.stringify([{lat: null, doy: 140}])
    const hook = {...Chart, el}
    hook.renderChart()
    expect(el.textContent).toContain('No observations to display')
    expect(el.querySelector('svg')).toBeNull()
    hook.destroyed()
  })

  test('onset draws one line and date, without any duration band or median', () => {
    const el = render({event: 'onset', generation: 'unknown', target_lat: 35,
      low_doy: 150, high_doy: 150,
      contours: [{lat: 30, low_doy: 140, high_doy: 140}, {lat: 40, low_doy: 160, high_doy: 160}]})
    expect(el.querySelectorAll('.prediction-boundary')).toHaveLength(1)
    expect(el.querySelectorAll('.prediction-median')).toHaveLength(0)
    expect(el.querySelectorAll('.prediction-outer-band')).toHaveLength(0)
    expect(el.querySelectorAll('.prediction-date-marker')).toHaveLength(1)
    expect([...el.querySelectorAll('path')].some(p => p.getAttribute('d').endsWith('Z'))).toBe(false)
    expect(el.querySelector('.prediction-boundary').getAttribute('stroke-dasharray')).toBeNull()
  })

  test('winter uses translated narrow polygons, not a December-to-January year-wide fill', () => {
    const el = render({event: 'emergence', generation: 'agamic', wrap_year: true,
      target_lat: 35, low_doy: 360, high_doy: 10,
      contours: [{lat: 30, low_doy: -5, high_doy: 10}, {lat: 40, low_doy: -10, high_doy: 5}]})
    const paths = [...el.querySelectorAll('.prediction-boundary')]
    expect(paths).toHaveLength(10)
    expect(paths.every(p => p.getAttribute('stroke-dasharray') === '6,4')).toBe(true)
    const polygons = [...el.querySelectorAll('path')].filter(p => p.getAttribute('d').endsWith('Z'))
    expect(polygons).toHaveLength(5)
    for (const p of polygons) {
      const coords = p.getAttribute('d').match(/-?\d+(?:\.\d+)?/g).map(Number)
      const xs = coords.filter((_, i) => i % 2 === 0)
      expect(Math.max(...xs) - Math.min(...xs)).toBeLessThan(30)
    }
  })

  test('mobile layout puts the legend above the plot and uses readable quarterly ticks', () => {
    const el = document.createElement('div')
    Object.defineProperties(el, {clientWidth: {value: 340}, clientHeight: {value: 540}})
    el.dataset.points = JSON.stringify([{lat: 35, doy: 140, generation: 'sexgen', phenophase: 'developing'}])
    const hook = {...Chart, el}
    hook.renderChart()
    expect(hook._width).toBe(272)
    expect([...el.querySelectorAll('.month-axis .tick text')].map(t => t.textContent))
      .toEqual(['Jan', 'Apr', 'Jul', 'Oct'])
    expect([...el.querySelectorAll('.legend text')].every(t => Number(t.getAttribute('y')) < 0)).toBe(true)
    hook.destroyed()
  })
})
