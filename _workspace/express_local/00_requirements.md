# 급행/완행 선택 기능 구현

## 사용자 요청
경로 검색 결과에서 급행/완행을 토글하여 각각의 소요시간을 확인할 수 있게 한다.

## 승인된 plan
`/Users/april/.claude/plans/serene-fluttering-pie.md`

## 핵심 결정사항
1. 경로는 Dijkstra가 완행 기준으로 찾은 그대로 유지
2. UI: `_RouteSummaryHeader` 하단 SegmentedButton (완행/급행)
3. 급행 미정차 구간은 자동으로 완행 시간 사용 (혼합 적용)
4. 데이터 + 토글 UI 한 PR

## 산출물
`_workspace/express_local/`
