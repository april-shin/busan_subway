# 급행 노선을 별도 논리 노선으로 모델링

## 사용자 요청
9호선 언주→마곡나루 같은 경로에서 Dijkstra가 실제 가장 빠른 "완행 1정거장 + 급행 환승" 경로를 자동 탐색하도록 그래프 확장.

## 승인된 plan
`/Users/april/.claude/plans/serene-fluttering-pie.md` 참조.

## 핵심 결정사항
1. 이번 PR: 그래프·경로 모델링만 (기존 토글 UI 유지)
2. 모드 전환 edge weight = 배차간격/2
3. 환승 대기 반영
4. 급행 세그먼트 UI는 "9호선 급행" 표시

## 산출물
`_workspace/express_routing/`
