# 환승 가이드 정보 추가

## 사용자 요청
경로 검색 결과에 각 환승역에서 **내리는 문 방향 / 몇 번 객차 / 몇 번 문** 정보가 필요하다.

## 승인된 플랜
`/Users/april/.claude/plans/serene-fluttering-pie.md` 참조.

## 사용자 결정사항
1. 데이터 소싱: 외부 API/크롤링 조사 (이번 PR에서는 스키마만 준비, 실제 크롤링은 후속)
2. 데이터 키: 4-tuple `{환승역, 도착노선, 도착방향(up/down), 목적노선} → {doorSide, car, door, note}`
3. UI 위치: 환승 행(`_TransferRow`) 내부에 확장

## TDD 순서
1. TransferGuide 엔티티 테스트 → 구현 → build_runner
2. LocalDataSource.loadTransferGuides 테스트 → 구현
3. SearchRoute 4-tuple 매칭 테스트 → RouteResult 필드 추가 + _buildSegments 확장 → build_runner
4. _TransferRow 위젯 테스트 → UI 확장
5. IMPROVE: _buildGuideKey 함수 추출

## 산출물 경로
`_workspace/transfer_guide/`
