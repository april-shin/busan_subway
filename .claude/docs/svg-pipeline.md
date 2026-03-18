# SVG 데이터 파이프라인

원본 SVG(`seoul_metro_map.svg`)에서 앱 에셋을 생성하는 3단계 파이프라인:

```bash
# 1단계: SVG에서 역 좌표 추출
dart run tool/extract_svg_stations.dart
# → assets/json/svg_station_coords.json (653개 역의 SVG 좌표)

# 2단계: 역/노선/연결 JSON 생성 (SVG 좌표 참조)
dart run tool/generate_station_data.dart
# → assets/json/stations.json, connections.json, lines.json, transfer_times.json

# 3단계: WebView용 HTML 생성 (SVG를 HTML에 인라인 삽입)
dart run tool/build_map_html.dart
# → assets/html/map.html
```

**중요:** 원본 SVG를 수정한 후 반드시 3단계 파이프라인을 순서대로 재실행해야 한다.

## SVG 좌표 추출 (`extract_svg_stations.dart`)

- SVG의 `<text data-station="역명">` 라벨과 가장 가까운 `<circle>` 좌표를 매칭
- 역명의 줄바꿈 문자 자동 제거 (SVG `<tspan>` 분할 역명 처리)
- 모든 `data-line` 값을 추출 (GTX-A `1-GA` 포함)

## HTML 빌드 (`build_map_html.dart`)

- 원본 SVG를 HTML 템플릿에 인라인 삽입
- SVG 최소 변환: `width="100%" height="100%"` → `width="2416" height="1560"`, `style="background: white;"` 제거
- JS로 줌/팬, 탭 감지, 경로 하이라이트, 마커, 툴팁 기능 구현
- 오버스크롤 여백: 상하좌우 70px (`clampTranslation` 함수)

## JS 성능 패턴 (저사양 기기 대응)

- **rAF 스케줄링**: `pointermove`/`wheel`/`resize` 이벤트에서 `scheduleTransform()` 사용. `rafPending` 플래그로 프레임당 1회만 `applyTransform()` 실행. 초기화(`setInitialView`)나 애니메이션(`panTo`)에서는 직접 `applyTransform()` 호출.
- **CSS 클래스 기반 강조/흐림**: 노선 강조 시 개별 `style.opacity` 대신 `.dimmed` CSS 클래스를 토글. `transition: opacity 0.3s`는 CSS에서 일괄 적용.
- **overlay circle 분리**: overlay 내부에서 생성하는 모든 `<circle>`에 `data-overlay` 속성 부여. 강조 처리 시 `circle:not([data-overlay])` 셀렉터로 원본 SVG circle만 대상. `closest()` DOM 탐색 불필요.

## SVG 스타일 규격 (원본 SVG 교체 시에도 유지해야 할 값)

| 요소 | 속성 | 값 | 비고 |
|---|---|---|---|
| 역이름 텍스트 (`<text>`) | `font-size` | `12px` | 인라인 스타일 |
| 역이름 텍스트 (`<text>`) | CSS `stroke` | `white`, `2px`, `paint-order: stroke` | `build_map_html.dart`의 `<style>` 블록에서 적용, 흰색 테두리 |
| 역이름 줄바꿈 | `<tspan>` | `dy="14"` | 띄어쓰기 포함 역이름은 `<tspan>`으로 분리 |
| 일반역 원 (`<circle>`) | `r` | `4.5` | |
| 환승역 원 (`<circle>`) | `r` | `5` | |
| 노선 경로 (`<path>`) | `stroke-width` | `3` | 2호선 제외 |
| 2호선 경로 (`data-line="3-2"`) | `stroke-width` | `4` | 순환+지선 |

## SVG data-line 매핑

노선 코드 매핑 테이블은 `.claude/docs/lines-reference.md`의 "SVG data-line 매핑" 섹션 참조.
