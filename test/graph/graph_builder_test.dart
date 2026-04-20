import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/graph/graph_builder.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/entities/express_skip_edge.dart';

void main() {
  late GraphBuilder builder;

  setUp(() {
    builder = GraphBuilder();
  });

  group('GraphBuilder', () {
    test('builds graph with stations as nodes', () {
      final stations = [
        const Station(
          id: '201', name: '시청', lineId: '2',
          latitude: 37.56, longitude: 126.97,
        ),
        const Station(
          id: '202', name: '을지로입구', lineId: '2',
          latitude: 37.56, longitude: 126.98,
        ),
      ];

      final graph = builder.build(
        stations: stations,
        connections: [],
        transferTimes: {},
      );

      expect(graph.nodeCount, 2);
      expect(graph.containsNode('201_2'), true);
      expect(graph.containsNode('202_2'), true);
    });

    test('builds graph with connections as bidirectional edges', () {
      final stations = [
        const Station(
          id: '201', name: '시청', lineId: '2',
          latitude: 37.56, longitude: 126.97,
        ),
        const Station(
          id: '202', name: '을지로입구', lineId: '2',
          latitude: 37.56, longitude: 126.98,
        ),
      ];

      final connections = [
        const Connection(
          fromStationId: '201', toStationId: '202',
          lineId: '2', travelTimeSeconds: 90,
        ),
      ];

      final graph = builder.build(
        stations: stations,
        connections: connections,
        transferTimes: {},
      );

      final neighbors201 = graph.getNeighbors('201_2');
      final neighbors202 = graph.getNeighbors('202_2');

      expect(neighbors201.length, 1);
      expect(neighbors201.first.toNodeId, '202_2');
      expect(neighbors201.first.weightSeconds, 90);

      expect(neighbors202.length, 1);
      expect(neighbors202.first.toNodeId, '201_2');
    });

    test('builds transfer edges between same-name stations', () {
      final stations = [
        const Station(
          id: '214', name: '교대', lineId: '2',
          latitude: 37.49, longitude: 127.01,
          isTransfer: true, transferLines: ['2', '3'],
        ),
        const Station(
          id: '320', name: '교대', lineId: '3',
          latitude: 37.49, longitude: 127.01,
          isTransfer: true, transferLines: ['2', '3'],
        ),
      ];

      final transferTimes = {'교대_2_3': 180};

      final graph = builder.build(
        stations: stations,
        connections: [],
        transferTimes: transferTimes,
      );

      final neighbors214 = graph.getNeighbors('214_2');
      final neighbors320 = graph.getNeighbors('320_3');

      expect(neighbors214.length, 1);
      expect(neighbors214.first.isTransfer, true);
      expect(neighbors214.first.weightSeconds, 180);

      expect(neighbors320.length, 1);
      expect(neighbors320.first.isTransfer, true);
    });

    test('uses default transfer time when not specified', () {
      final stations = [
        const Station(
          id: '214', name: '교대', lineId: '2',
          latitude: 37.49, longitude: 127.01,
          isTransfer: true, transferLines: ['2', '3'],
        ),
        const Station(
          id: '320', name: '교대', lineId: '3',
          latitude: 37.49, longitude: 127.01,
          isTransfer: true, transferLines: ['2', '3'],
        ),
      ];

      final graph = builder.build(
        stations: stations,
        connections: [],
        transferTimes: {},
      );

      final neighbors = graph.getNeighbors('214_2');
      expect(neighbors.first.weightSeconds, 180); // default
    });

    test('non-transfer stations do not get transfer edges', () {
      final stations = [
        const Station(
          id: '202', name: '을지로입구', lineId: '2',
          latitude: 37.56, longitude: 126.98,
          isTransfer: false,
        ),
      ];

      final graph = builder.build(
        stations: stations,
        connections: [],
        transferTimes: {},
      );

      expect(graph.getNeighbors('202_2'), isEmpty);
    });
  });

  group('GraphBuilder — 급행 모델링', () {
    // 9호선 일부: 902(개화) 905(김포공항) 907(가양) 910(염창)
    // 급행은 902→905→907→910 무정차로 운행. 완행은 모든 인접역 연결.
    final stations = [
      const Station(
          id: '902', name: '개화', lineId: '9',
          latitude: 0, longitude: 0),
      const Station(
          id: '903', name: '김포공항', lineId: '9',
          latitude: 0, longitude: 0),
      const Station(
          id: '904', name: '공항시장', lineId: '9',
          latitude: 0, longitude: 0),
      const Station(
          id: '905', name: '신방화', lineId: '9',
          latitude: 0, longitude: 0),
      const Station(
          id: '906', name: '마곡나루', lineId: '9',
          latitude: 0, longitude: 0),
      const Station(
          id: '907', name: '양천향교', lineId: '9',
          latitude: 0, longitude: 0),
    ];
    final connections = [
      const Connection(
          fromStationId: '902', toStationId: '903', lineId: '9',
          travelTimeSeconds: 60),
      const Connection(
          fromStationId: '903', toStationId: '904', lineId: '9',
          travelTimeSeconds: 60),
      const Connection(
          fromStationId: '904', toStationId: '905', lineId: '9',
          travelTimeSeconds: 60),
      const Connection(
          fromStationId: '905', toStationId: '906', lineId: '9',
          travelTimeSeconds: 60),
      const Connection(
          fromStationId: '906', toStationId: '907', lineId: '9',
          travelTimeSeconds: 60),
    ];
    final expressEdges = [
      const ExpressSkipEdge(
          lineId: '9', fromStationId: '902', toStationId: '905',
          seconds: 180, skippedStationIds: ['903', '904']),
      const ExpressSkipEdge(
          lineId: '9', fromStationId: '905', toStationId: '907',
          seconds: 120, skippedStationIds: ['906']),
    ];

    test('급행 정차역에 _E 노드가 추가된다', () {
      final graph = builder.build(
        stations: stations,
        connections: connections,
        transferTimes: {},
        expressSkipEdges: expressEdges,
      );

      expect(graph.containsNode('902_9E'), isTrue);
      expect(graph.containsNode('905_9E'), isTrue);
      expect(graph.containsNode('907_9E'), isTrue);
      // 급행 미정차역은 _E 노드 없음
      expect(graph.containsNode('903_9E'), isFalse);
      expect(graph.containsNode('906_9E'), isFalse);
    });

    test('급행 노드 사이에 양방향 9E edge가 생성된다', () {
      final graph = builder.build(
        stations: stations,
        connections: connections,
        transferTimes: {},
        expressSkipEdges: expressEdges,
      );

      final fwd = graph.getNeighbors('902_9E');
      final express = fwd.firstWhere(
        (e) => e.toNodeId == '905_9E',
        orElse: () => throw StateError('급행 edge 누락'),
      );
      expect(express.lineId, '9E');
      expect(express.weightSeconds, 180);
      expect(express.isTransfer, isFalse);

      final rev = graph.getNeighbors('905_9E');
      expect(
        rev.any((e) => e.toNodeId == '902_9E' && e.weightSeconds == 180),
        isTrue,
      );
    });

    test('9호선 모드 전환 edge 는 weight 0 (정책: 같은 플랫폼에서 환승)', () {
      final graph = builder.build(
        stations: stations,
        connections: connections,
        transferTimes: {},
        expressSkipEdges: expressEdges,
        headwaySeconds: const {'9': 240}, // 배차 4분이어도 9호선은 0초 강제
      );

      final localToExpress = graph
          .getNeighbors('905_9')
          .firstWhere((e) => e.toNodeId == '905_9E');
      expect(localToExpress.isTransfer, isTrue);
      expect(localToExpress.lineId, '9M');
      expect(localToExpress.weightSeconds, 0,
          reason: '9호선 모드 전환은 같은 플랫폼이라 대기 0초');

      final expressToLocal = graph
          .getNeighbors('905_9E')
          .firstWhere((e) => e.toNodeId == '905_9');
      expect(expressToLocal.isTransfer, isTrue);
      expect(expressToLocal.weightSeconds, 0);
    });

    test('headwaySeconds가 없어도 9호선 모드 전환 edge weight는 0', () {
      final graph = builder.build(
        stations: stations,
        connections: connections,
        transferTimes: {},
        expressSkipEdges: expressEdges,
      );

      final modeEdge = graph
          .getNeighbors('905_9')
          .firstWhere((e) => e.toNodeId == '905_9E');
      expect(modeEdge.weightSeconds, 0);
    });

    test('비-9호선(예: 공항철도 A) 모드 전환 edge 는 기존 정책(배차/2) 유지',
        () {
      // 가상의 노선 'A' (공항철도) 데이터로 회귀 검증.
      final airportStations = const [
        Station(id: 'A01', name: '서울역A', lineId: 'A', latitude: 0, longitude: 0),
        Station(id: 'A02', name: '공덕A', lineId: 'A', latitude: 0, longitude: 0),
        Station(id: 'A03', name: '홍대입구A', lineId: 'A', latitude: 0, longitude: 0),
      ];
      final airportConnections = const [
        Connection(fromStationId: 'A01', toStationId: 'A02', lineId: 'A', travelTimeSeconds: 100),
        Connection(fromStationId: 'A02', toStationId: 'A03', lineId: 'A', travelTimeSeconds: 100),
      ];
      final airportExpress = const [
        ExpressSkipEdge(
            lineId: 'A',
            fromStationId: 'A01',
            toStationId: 'A03',
            seconds: 120,
            skippedStationIds: ['A02']),
      ];

      final graph = builder.build(
        stations: airportStations,
        connections: airportConnections,
        transferTimes: {},
        expressSkipEdges: airportExpress,
        headwaySeconds: const {'A': 240}, // 배차 4분 → 모드 전환 120초
      );

      final modeEdge = graph
          .getNeighbors('A01_A')
          .firstWhere((e) => e.toNodeId == 'A01_AE');
      expect(modeEdge.lineId, 'AM');
      expect(modeEdge.weightSeconds, 120,
          reason: '비-9호선은 기존 정책(배차/2) 유지');
    });

    test('expressSkipEdges가 비어있으면 _E 노드와 모드 전환 edge가 없다', () {
      final graph = builder.build(
        stations: stations,
        connections: connections,
        transferTimes: {},
      );

      expect(graph.containsNode('902_9E'), isFalse);
      expect(graph.containsNode('905_9E'), isFalse);
      expect(graph.getNeighbors('905_9').any((e) => e.lineId == '9M'), isFalse);
    });

    test('환승 edge에 도착 노선의 배차/2가 추가된다 (양방향 비대칭)', () {
      // 같은 이름 환승역: 노선 2(헤드웨이 240) ↔ 노선 3(헤드웨이 360)
      final transferStations = [
        const Station(
            id: '203', name: '을지로3가', lineId: '2',
            latitude: 0, longitude: 0,
            isTransfer: true, transferLines: ['2', '3']),
        const Station(
            id: '316', name: '을지로3가', lineId: '3',
            latitude: 0, longitude: 0,
            isTransfer: true, transferLines: ['2', '3']),
      ];
      final transferTimes = {'을지로3가_2_3': 60};
      final headway = {'2': 240, '3': 360}; // 4분, 6분

      final graph = builder.build(
        stations: transferStations,
        connections: [],
        transferTimes: transferTimes,
        headwaySeconds: headway,
      );

      // 2→3: transfer 60 + 도착=3의 wait 180 = 240
      final from2 = graph
          .getNeighbors('203_2')
          .firstWhere((e) => e.toNodeId == '316_3');
      expect(from2.weightSeconds, 240);
      expect(from2.isTransfer, isTrue);

      // 3→2: transfer 60 + 도착=2의 wait 120 = 180
      final from3 = graph
          .getNeighbors('316_3')
          .firstWhere((e) => e.toNodeId == '203_2');
      expect(from3.weightSeconds, 180);
      expect(from3.isTransfer, isTrue);
    });

    test('headwaySeconds가 비어있으면 환승 weight는 transferTime 그대로 (레거시 호환)', () {
      final transferStations = [
        const Station(
            id: '203', name: '을지로3가', lineId: '2',
            latitude: 0, longitude: 0,
            isTransfer: true, transferLines: ['2', '3']),
        const Station(
            id: '316', name: '을지로3가', lineId: '3',
            latitude: 0, longitude: 0,
            isTransfer: true, transferLines: ['2', '3']),
      ];
      final graph = builder.build(
        stations: transferStations,
        connections: [],
        transferTimes: {'을지로3가_2_3': 60},
      );

      final fwd = graph
          .getNeighbors('203_2')
          .firstWhere((e) => e.toNodeId == '316_3');
      // headwaySeconds 빈 맵 → 대기 시간 추가 안 함
      expect(fwd.weightSeconds, 60);
    });
  });
}
