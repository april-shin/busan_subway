import '../entities/arrival_info.dart';

abstract class ArrivalRepository {
  Future<List<ArrivalInfo>> getArrivalInfo(String stationName);
}
