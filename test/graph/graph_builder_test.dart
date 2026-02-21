import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/graph/graph_builder.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/domain/entities/connection.dart';

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
}
