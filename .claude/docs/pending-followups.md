# 후속 작업 (handoff)

> 기록일 2026-07-26 · 관련 커밋 `claude/arrival-overrides-freezed3-riverpod3` (fac3643)
> 배경: 8호선 남한산성입구 도착정보 미표시 수정 → 조사 중 freezed2/riverpod2 툴체인이
> Dart 3.11.5와 비호환(build_runner 데드락)임이 드러나 freezed3/riverpod3 마이그레이션까지 수행.
> 관련 메모리: `arrival-api-station-name-overrides`, `toolchain-dart311-freezed3-riverpod3`, `station-data-pipeline-drift`

## P1 — 마이그레이션 검증 (2026-07-26 대부분 완료)
freezed3/riverpod3 마이그레이션은 `flutter analyze`(에러 0) + `flutter test`(651 pass)로만 검증됐었음.
진행 결과:
- [x] **code / requirements 리뷰 루프** 완료 (subway-code-reviewer + subway-requirements-reviewer).
      판정: CRITICAL 없음, ⛔ 4원칙 무손상, 원 요청(도착정보) 충족 ~100%. main 유지 가능.
- [x] **리뷰 발견 이슈 수정 3건** (working tree 미커밋 상태):
  - A. `main.dart` — riverpod3 자동 재시도(v3 신규 동작)가 API 일일한도 소진 위험 →
       `ProviderScope(retry: (_,_) => null)` 로 v2 동작(재시도 없음) 복원.
  - B. `arrival_info_dto.dart` — freezed3+json_serializable 의 `invalid_annotation_target`
       warning 14건 → 파일 국소 `// ignore_for_file` 로 억제(전역 아님). analyze warning 0 회복.
  - C. `live_train_provider.dart` — `_stripStationAlias` 무조건 적용이 정식명에 괄호가 있는
       역(관악산(서울대)·총신대입구(이수))의 라이브맵 매칭을 파괴 → "정확매칭 우선, strip 폴백"
       으로 전환. (기존 버그, 마이그레이션 회귀 아님. 오목교/신정 strip 케이스 보존 확인.)
  - 검증: analyze lib 에러·warning 0(info 6건은 P3), test 651 pass / 1 fail(P2 동일).
- [x] **앱 실런타임 스모크 테스트** — 시뮬레이터(iPhone 17 Pro, 마이그레이션 fac3643 빌드)에서 완료:
      홈 렌더 / 역선택(allStationsProvider·freezed3 Station·go_router) / 지도탭 툴팁(JS↔Flutter 채널) /
      경로계산·하이라이트·마커(Dijkstra·activeRouteFilter) / **도착정보 화면 실데이터 렌더**(freezed3
      ArrivalInfo·arrivalInfoProvider riverpod3 family) / **인바운드 역명 복원 실동작**(성균관대·평택·
      남영·서정리) / **리프레시 재fetch**(riverpod3 프로바이더 무효화 생명주기 정상). 런타임 예외·
      레드스크린 전무. **단, 실시간 열차 아이콘(4원칙) 시각 캡처는 미달성** — 테스트 경로(1호선 최북단
      소요산→서울역)의 필터 방향에 마침 열차 없음(실 API 상태, 버그 아님). 4원칙 JS는 마이그레이션
      무관 + 회귀테스트 통과로 방어됨. 원하면 혼잡 노선(2호선 등) 경로로 아이콘 육안 확인 가능.
- [ ] **미커밋 A/B/C 커밋** — 현재 main 브랜치라 정책상 브랜치 분리 후 커밋 필요. 사용자 지시 대기.
- [x] main 머지 — fac3643 이미 main 에 존재(별도 머지 불필요).

### P1 잔여 경미 이슈 (리뷰 발견, 선택)
- [ ] `station_api_name_overrides.dart` 주석 과장: "동명이역 부재를 테스트가 강제한다"지만 실제
      테스트는 키의 stations.json 존재·값충돌만 검증(단일출현 미검증). 주석 완화 또는 단일출현 테스트 추가.
- [ ] `4.19 민주묘지`(우이신설) 등 공백 포함 질의명의 Dio path 인코딩 앱 경로 1회 실측(리스크 낮음).
- [ ] 프로세스: 버그수정+대규모 마이그레이션이 단일 커밋(fac3643)에 묶여 bisect/롤백 추적성 저하(기록용).

## P2 — 유일하게 실패하는 테스트 (2026-07-26 완료)
`test/integration/realtime_arrival_all_stations_test.dart` (setUpAll 실패) 해결.
- 수행(권장 1+2+3 병행):
  1. `dart_test.yaml` 신설 — 실 네트워크 호출 테스트만 `real-api` 태그로 구분해 기본 실행 제외(skip).
     ⚠️ `integration` 태그는 실 API 를 안 쓰는 로컬 통합 테스트(find_path_full_coverage,
     transfer_membership)에도 붙어 있어 태그 전체 skip 은 커버리지 회귀 → `real-api` 로 좁힘.
     명시 실행: `flutter test --run-skipped --tags real-api`.
  2. 테스트 env 변수명 `SEOUL_API_KEY` → `SEOUL_SUBWAY_API_KEY`(정식명) 정정 + 키 없으면
     `fail()` 대신 graceful **skip**(`skip: skipReason`, 등록 시점 평가).
  3. 데이터소스 에러 메시지 드리프트 정정: `seoul_api_data_source.dart:43,47`
     `SEOUL_API_KEY` → `SEOUL_SUBWAY_API_KEY`(리뷰 LOW).
- 검증: 기본 `flutter test` → **651 pass / 1 skip(real-api) / 0 fail**. 로컬 통합 테스트 2개는
  계속 기본 실행됨(커버리지 유지). analyze lib/test 에러·warning 0.
- 잔여: CLAUDE.md "환경 설정" 섹션의 `SEOUL_API_KEY` 표기는 P5(문서 현행화)에서 정정.

## P3 — riverpod 3 정리 (2026-07-26 완료)
`unnecessary_import` 6건 제거: 아래 6개 프로바이더 파일에서 중복 `import
'package:flutter_riverpod/flutter_riverpod.dart';` 삭제(riverpod_annotation 가 대체).
`arrival_providers.dart`, `timetable_providers.dart`, `feedback_provider.dart`,
`home_station_provider.dart`, `live_train_provider.dart`, `subway_map_providers.dart`.
live_train/subway_map 은 `legacy.dart`(StateProvider/StateNotifier) 유지.
검증: analyze lib unnecessary_import 0, 전체 test 651 pass/1 skip/0 fail.

## P4 — 도착 API 데이터 후속 (station_api_name_overrides.dart)
- [ ] **세종대왕릉/신둔도예촌 중복역**: stations.json에 `신둔도예촌`(C29)·`세종대왕릉`(C32)이 위경도 다른 별개 역으로 공존. API는 `세종대왕릉` INFO-200, `신둔도예촌`만 응답. 정합성 확인 후 치환맵 추가 판단. (별도 태스크 `task_ed103f8a`로도 등록됨)
- [ ] **응암(6호선)·자양(7호선)** known-open: 반복 조회 INFO-200이나 정식 API명 미확정 → 치환맵 제외 중. 열차 있을 때 `realtimePosition`의 `statnNm`으로 재확인.
- 조사법·현황은 파일 상단 주석 + 메모리 `arrival-api-station-name-overrides` 참조.

## P5 — 문서/빌드 명령 현행화 (2026-07-26 대부분 완료)
- [x] CLAUDE.md "빌드 및 개발 명령어" + "코드 생성" 섹션의 `--delete-conflicting-outputs` 제거
      → `dart run build_runner build`(watch 동일)로 갱신. 구 삭제형 플래그 위험 경고 주석 추가.
- [x] CLAUDE.md "환경 설정" 섹션 `SEOUL_API_KEY` → `SEOUL_SUBWAY_API_KEY`(정식명) 정정
      + 데이터소스가 읽는 키임을 명시. (P2 잔여 문서 항목 흡수)
- [ ] pubspec `version: 1.0.3+5` 는 세션 시작 전부터 있던 변경(이번 작업 아님). **릴리스 의도 확인 필요**(사용자 판단 사안).
