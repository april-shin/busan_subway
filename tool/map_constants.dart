/// 지도 렌더링 상수의 **단일 소스**. `tool/build_map_html.dart`(JS/CSS 로 주입)와
/// `tool/line_badges.dart`(배지 배치 비용 평가), 그리고 테스트가 같은 값을 쓴다.
///
/// 예전에는 JS 의 `TEXT_BASE_FONT_SIZE`/`TEXT_COMP_FLOOR`/`CANVAS_W·H` 와 배지 모듈의
/// `_kBadgeFont`/`_kCompMax`/캔버스 크기가 따로 적혀 있어, 한쪽만 바꾸면 배지 배치 평가와
/// 테스트가 조용히 어긋났다. 이제 값은 여기에만 있다.
library;

/// 역명 라벨 기본 글자 크기(px) = JS `TEXT_BASE_FONT_SIZE`. 배지 글자도 같은 크기를 쓴다.
const double kTextBaseFontSize = 12;

/// 줌아웃 시 글자 보정 하한 = JS `TEXT_COMP_FLOOR` = 분자/분모.
/// JS 소스가 `2 / 3` 으로 읽히도록 분수 그대로 주입한다([kTextCompFloorNum]/[kTextCompFloorDen]).
const int kTextCompFloorNum = 2;
const int kTextCompFloorDen = 3;
const double kTextCompFloor = kTextCompFloorNum / kTextCompFloorDen;

/// 최대 줌아웃에서 보정계수 `f = 1/cs` 의 최댓값(= 1 / [kTextCompFloor] = 1.5).
const double kTextCompMax = kTextCompFloorDen / kTextCompFloorNum;

/// 지도 캔버스 크기(원본 SVG 좌표계) = JS `CANVAS_W`/`CANVAS_H`.
const double kCanvasW = 2416;
const double kCanvasH = 1560;

/// JS/CSS 소스에 숫자를 넣을 때 쓴다. 정수값은 소수점 없이(`12`), 아니면 그대로(`1.5`).
String jsNum(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
