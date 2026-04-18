// 남은시간(remainingSeconds)을 경로의 뒤에서부터 역순으로 소비하여
// 열차의 현재 위치 상태를 산출하는 순수 함수.
//
// 요구사항 `_workspace/00_requirements.md` 의 알고리즘 의사코드를 구현한다.
// - 주행 중: 세그먼트 내부 보간(progress)
// - 정차 중: 해당 역 좌표에 고정(isDwelling=true, progress=0.0)
// - 경로 소진 시: outOfPath=true + 경로 시작점 뒤에 남은 초(remainingAfterPath)
//
// 호출측은 outOfPath=true 를 받으면 pathToTarget 앞에 이전 역을 prepend 하여
// 경로를 확장한 뒤 재호출한다.

/// 열차 위치 역산 결과.
///
/// - [outOfPath] 가 true 면 호출측이 pathToTarget 을 이전 역으로 확장해야 한다.
/// - [segmentIndex] 는 주행 중인 세그먼트 인덱스, 또는 정차 중이면 정차 직전
///   도착 세그먼트 인덱스(= 해당 역에 도착시킨 세그먼트)이다.
///   즉 정차역은 path[segmentIndex] 가 아니라 path[segmentIndex] 도착점.
///   본 구현에서는 정차 중일 때 segmentIndex=i 는 "i 번째 세그먼트 이후 정차"
///   를 의미하며, 좌표는 path[segmentIndex](= 다음 세그먼트의 출발역)에 해당한다.
/// - [progress] 는 0.0~1.0, 정차 중이면 0.0.
/// - [remainingAfterPath] 는 outOfPath=true 일 때만 유효.
typedef TrainPositionResult = ({
  bool outOfPath,
  int segmentIndex,
  double progress,
  bool isDwelling,
  int remainingAfterPath,
});

/// [remainingSeconds] 를 경로 뒤에서부터 역산하여 열차 위치를 반환한다.
///
/// [segmentTravelTimes] 는 "주행시간만" 의 리스트이며 세그먼트 수 n 과 같다.
/// (경로 점 개수는 n+1.) 빈 리스트는 허용하지 않는다.
/// [dwellSeconds] 는 중간역 정차시간(전역 고정 상수).
///
/// 경계 규칙:
/// - `remainingSeconds <= 0`: 이미 도착. 마지막 세그먼트 끝 반환.
/// - `remainingSeconds == s[i]`: `t_rem <= s[i]` 로 판정하여 주행 쪽에 귀속
///   (progress=0.0, 즉 해당 세그먼트 시작).
/// - 정차 경계(`t_rem == dwell`): `t_rem <= dwell` 로 정차 쪽에 귀속.
TrainPositionResult estimateTrainPosition({
  required int remainingSeconds,
  required List<int> segmentTravelTimes,
  required int dwellSeconds,
}) {
  if (segmentTravelTimes.isEmpty) {
    throw ArgumentError('segmentTravelTimes 는 비어 있을 수 없다.');
  }

  final n = segmentTravelTimes.length;

  // 이미 도착했거나 남은시간이 없으면 마지막 세그먼트 끝으로 고정.
  if (remainingSeconds <= 0) {
    return (
      outOfPath: false,
      segmentIndex: n - 1,
      progress: 1.0,
      isDwelling: false,
      remainingAfterPath: 0,
    );
  }

  var tRem = remainingSeconds;

  // 뒤에서부터 세그먼트/정차를 소비.
  for (var i = n - 1; i >= 0; i--) {
    final segTime = segmentTravelTimes[i];

    // 주행 구간 내부 (경계 t_rem == segTime 은 주행 쪽 → progress=0.0)
    if (tRem <= segTime) {
      final progress = segTime <= 0 ? 0.0 : (segTime - tRem) / segTime;
      return (
        outOfPath: false,
        segmentIndex: i,
        progress: progress,
        isDwelling: false,
        remainingAfterPath: 0,
      );
    }
    tRem -= segTime;

    // 세그먼트 i 이전(= 출발역 path[i]) 에서의 정차는, 그 역이 중간역일 때만 발생.
    // i > 0 인 경우: path[i] 는 이전 세그먼트 path[i-1]→path[i] 의 도착역이자
    // 현재 세그먼트의 출발역이며, 중간역이므로 정차가 존재한다.
    if (i > 0) {
      if (tRem <= dwellSeconds) {
        return (
          outOfPath: false,
          segmentIndex: i,
          progress: 0.0,
          isDwelling: true,
          remainingAfterPath: 0,
        );
      }
      tRem -= dwellSeconds;
    }
  }

  // 경로 시작점보다 더 뒤에 남은 시간이 있다 → 경로 확장 필요.
  return (
    outOfPath: true,
    segmentIndex: 0,
    progress: 0.0,
    isDwelling: false,
    remainingAfterPath: tRem,
  );
}
