import 'package:latlong2/latlong.dart';

import 'trafiklab_api.dart';
import 'trafiklab_models.dart' as tl;
import '../gtfs/gtfs_models.dart' as gtfs;

class TrafikLabRepository {
  TrafikLabRepository(this._api) : _distance = const Distance();

  final TrafikLabApi _api;
  final Distance _distance;

  /// Search stops by text and return them.
  Future<List<gtfs.Stop>> searchStops(String query) async {
    final raw = await _api.searchStops(query);
    return raw
        .map((s) => gtfs.Stop(id: s.id, name: s.name, lat: s.lat, lon: s.lon))
        .toList();
  }

  /// Return nearest stops to the provided point. Uses the `searchStops` as a
  /// scaffold — adapt to a real TrafikLab "nearby" endpoint if available.
  Future<List<gtfs.Stop>> nearestStops(LatLng user, {int limit = 10}) async {
    final all = await _api.searchStops('');
    all.sort((a, b) => _distance(user, a.point).compareTo(_distance(user, b.point)));
    return all
        .take(limit)
        .map((s) => gtfs.Stop(id: s.id, name: s.name, lat: s.lat, lon: s.lon))
        .toList();
  }

  Future<List<gtfs.Departure>> departuresForStop(String stopId) async {
    final raw = await _api.departuresForStop(stopId);
    return raw
        .map((d) => gtfs.Departure(
              trip: gtfs.TripInfo(id: d.route, routeId: d.route, serviceId: 'RT', headsign: d.route),
              route: gtfs.RouteInfo(id: d.route, shortName: d.route, longName: d.route),
              arrivalTime: d.time,
              stop: gtfs.Stop(id: d.stop.id, name: d.stop.name, lat: d.stop.lat, lon: d.stop.lon),
            ))
        .toList();
  }

  Future<tl.TripPlan> planTrip(LatLng origin, LatLng destination) async {
    return await _api.planTrip(origin, destination);
  }

  /// Fetch delay statistics; optional `lineNumber` to filter.
  Future<List<tl.DelayStat>> getDelayStats({String? lineNumber}) async {
    final raw = await _api.getDelayStats(lineNumber: lineNumber);
    return raw.map((d) => tl.DelayStat.fromJson({
          'line': d.line,
          'delay_seconds': d.delaySeconds,
          'stop_id': d.stopId,
          'note': d.note,
        })).toList();
  }

  /// Fetch vehicle positions; optional `lineNumber` to filter.
  Future<List<tl.VehiclePosition>> getVehiclePositions({String? lineNumber}) async {
    final raw = await _api.vehiclePositions(lineNumber: lineNumber);
    return raw
        .map((v) => tl.VehiclePosition.fromJson({
              'id': v.id,
              'lat': v.lat,
              'lon': v.lon,
              'heading': v.heading,
              'trip_id': v.tripId,
              'line': v.route,
            }))
        .toList();
  }
}
