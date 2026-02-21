import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../data/local/local_data_source.dart';
import '../../../../data/repositories/station_repository_impl.dart';
import '../../../../domain/entities/station.dart';
import '../../../../domain/repositories/station_repository.dart';

part 'subway_map_providers.g.dart';

@riverpod
LocalDataSource localDataSource(Ref ref) {
  return LocalDataSource();
}

@riverpod
StationRepository stationRepository(Ref ref) {
  return StationRepositoryImpl(
    localDataSource: ref.watch(localDataSourceProvider),
  );
}

@riverpod
Future<List<Station>> allStations(Ref ref) {
  return ref.watch(stationRepositoryProvider).getAllStations();
}

class SelectedStationsNotifier extends StateNotifier<SelectedStations> {
  SelectedStationsNotifier() : super(const SelectedStations());

  void setDeparture(Station? station) {
    state = SelectedStations(
      departure: station,
      arrival: state.arrival,
    );
  }

  void setArrival(Station? station) {
    state = SelectedStations(
      departure: state.departure,
      arrival: station,
    );
  }

  void swap() {
    state = SelectedStations(
      departure: state.arrival,
      arrival: state.departure,
    );
  }

  void clear() {
    state = const SelectedStations();
  }
}

class SelectedStations {
  final Station? departure;
  final Station? arrival;

  const SelectedStations({this.departure, this.arrival});

  bool get isComplete => departure != null && arrival != null;
}

final selectedStationsProvider =
    StateNotifierProvider<SelectedStationsNotifier, SelectedStations>(
  (ref) => SelectedStationsNotifier(),
);

final tappedStationProvider = StateProvider<Station?>((ref) => null);
