import '../entities/route_result.dart';

abstract class RouteRepository {
  Future<RouteResult> searchRoute(String fromStationId, String toStationId);
}
