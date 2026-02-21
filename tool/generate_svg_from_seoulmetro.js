#!/usr/bin/env node
/**
 * 서울교통공사 사이버스테이션 노선 데이터 → SVG 변환 스크립트
 *
 * 입력: seoulmetro_lines_raw.js (var lines = {...})
 * 출력: assets/svg/seoul_subway_linemap_ko.svg
 *
 * 그리드: 305 columns x 200 rows, cellSize=5 → 1525x1000 px
 */

const fs = require('fs')
const path = require('path')

const CELL_SIZE = 5
const COLS = 305
const ROWS = 200
const WIDTH = COLS * CELL_SIZE
const HEIGHT = ROWS * CELL_SIZE
const LINE_WIDTH = 2.5
const STATION_RADIUS = 3
const INTERCHANGE_RADIUS = 4
const FONT_SIZE = 7
const LABEL_OFFSET = 6

// --- 1) 노선 데이터 파싱 (JavaScript 직접 평가) ---

const raw = fs.readFileSync(
  path.join(__dirname, 'seoulmetro_lines_raw.js'),
  'utf-8'
)

const lines = new Function(raw + '; return lines;')()

console.log(`${Object.keys(lines).length}개 노선 파싱 완료`)

// --- 2) SVG 생성 ---

function coordToPixel(coordStr) {
  const parts = coordStr.split(',').map(s => parseFloat(s.trim()))
  return { x: parts[0] * CELL_SIZE, y: parts[1] * CELL_SIZE }
}

function getLabelAnchorAndOffset(labelPos) {
  const pos = (labelPos || 'E').toUpperCase()
  const offsets = {
    N:  { dx: 0, dy: -LABEL_OFFSET, anchor: 'middle' },
    NE: { dx: LABEL_OFFSET, dy: -LABEL_OFFSET + 2, anchor: 'start' },
    E:  { dx: LABEL_OFFSET, dy: 3, anchor: 'start' },
    SE: { dx: LABEL_OFFSET, dy: LABEL_OFFSET + 2, anchor: 'start' },
    S:  { dx: 0, dy: LABEL_OFFSET + 5, anchor: 'middle' },
    SW: { dx: -LABEL_OFFSET, dy: LABEL_OFFSET + 2, anchor: 'end' },
    W:  { dx: -LABEL_OFFSET, dy: 3, anchor: 'end' },
    NW: { dx: -LABEL_OFFSET, dy: -LABEL_OFFSET + 2, anchor: 'end' },
  }
  return offsets[pos] || offsets.E
}

function escapeXml(str) {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}

const svgParts = []

// SVG 헤더
svgParts.push(`<?xml version="1.0" encoding="UTF-8"?>`)
svgParts.push(
  `<svg xmlns="http://www.w3.org/2000/svg" ` +
  `viewBox="0 0 ${WIDTH} ${HEIGHT}" ` +
  `width="${WIDTH}" height="${HEIGHT}" ` +
  `font-family="'Malgun Gothic', 'Apple SD Gothic Neo', sans-serif">`
)

// 배경
svgParts.push(`<rect width="${WIDTH}" height="${HEIGHT}" fill="white"/>`)

// 노선별 처리
for (const [lineId, lineData] of Object.entries(lines)) {
  const attr = lineData.attr || lineData
  const stations = lineData.stations
  if (!stations) continue

  const color = attr['data-color'] || '#999'
  const label = attr['data-label'] || lineId
  const lineWidthAttr = parseFloat(attr['data-lineWidth'] || LINE_WIDTH)

  // 흰색 노선(GTX-A 배경)은 건너뜀
  if (color === '#ffffff') continue

  svgParts.push(`\n<!-- ${label} (${lineId}) -->`)
  svgParts.push(`<g id="line-${lineId}" data-label="${escapeXml(label)}">`)

  // 경로 좌표 수집 (moveTo로 지선 분기 처리)
  const pathSegments = []
  let currentSegment = []

  for (const st of stations) {
    // indicator 노드는 건너뜀
    if (st['data-nodeType'] === 'indicator') continue

    const coords = st['data-coords']
    const moveTo = st['data-moveTo']

    // moveTo가 있으면 새 세그먼트 시작 (지선 분기점)
    if (moveTo) {
      if (currentSegment.length > 0) {
        pathSegments.push([...currentSegment])
      }
      currentSegment = [coordToPixel(moveTo)]
      // coords가 moveTo와 다르면 경로 포인트로 추가
      if (coords && coords !== moveTo) {
        currentSegment.push(coordToPixel(coords))
      }
      continue
    }

    if (!coords) continue
    currentSegment.push(coordToPixel(coords))
  }
  if (currentSegment.length > 0) {
    pathSegments.push(currentSegment)
  }

  // 노선 경로 그리기
  for (const segment of pathSegments) {
    if (segment.length < 2) continue
    let d = `M${segment[0].x},${segment[0].y}`
    for (let i = 1; i < segment.length; i++) {
      d += ` L${segment[i].x},${segment[i].y}`
    }
    svgParts.push(
      `  <path d="${d}" fill="none" stroke="${color}" ` +
      `stroke-width="${lineWidthAttr}" stroke-linecap="round" stroke-linejoin="round"/>`
    )
  }

  // 역 마커와 라벨
  const stationElements = []
  const labelElements = []

  for (const st of stations) {
    if (!st['station-nm'] || !st['data-coords']) continue
    if (st['data-nodeType'] === 'indicator') continue

    const { x, y } = coordToPixel(st['data-coords'])
    const name = st['station-nm']
    const isInterchange = st['data-marker'] === 'interchange'
    const r = isInterchange ? INTERCHANGE_RADIUS : STATION_RADIUS

    // 역 원형 마커
    stationElements.push(
      `  <circle cx="${x}" cy="${y}" r="${r}" ` +
      `fill="white" stroke="${isInterchange ? '#333' : color}" ` +
      `stroke-width="${isInterchange ? 1.2 : 1}"/>`
    )

    // 역명 라벨
    const labelInfo = getLabelAnchorAndOffset(st['data-labelPos'])
    const nameLines = name.split('\n')

    if (nameLines.length === 1) {
      labelElements.push(
        `  <text x="${x + labelInfo.dx}" y="${y + labelInfo.dy}" ` +
        `text-anchor="${labelInfo.anchor}" font-size="${FONT_SIZE}" ` +
        `fill="#333">${escapeXml(name)}</text>`
      )
    } else {
      // 여러 줄 역명
      labelElements.push(
        `  <text x="${x + labelInfo.dx}" y="${y + labelInfo.dy}" ` +
        `text-anchor="${labelInfo.anchor}" font-size="${FONT_SIZE}" fill="#333">`
      )
      for (let i = 0; i < nameLines.length; i++) {
        labelElements.push(
          `    <tspan x="${x + labelInfo.dx}" dy="${i === 0 ? 0 : FONT_SIZE + 1}">${escapeXml(nameLines[i])}</tspan>`
        )
      }
      labelElements.push(`  </text>`)
    }
  }

  svgParts.push(...stationElements)
  svgParts.push(...labelElements)
  svgParts.push(`</g>`)
}

svgParts.push(`</svg>`)

// --- 3) 파일 저장 ---

const outputPath = path.join(__dirname, '..', 'assets', 'svg', 'seoulmetro_cyber_station.svg')
fs.mkdirSync(path.dirname(outputPath), { recursive: true })
fs.writeFileSync(outputPath, svgParts.join('\n'), 'utf-8')

const size = fs.statSync(outputPath).size
console.log(`SVG 생성 완료: ${outputPath}`)
console.log(`파일 크기: ${(size / 1024).toFixed(1)} KB`)
