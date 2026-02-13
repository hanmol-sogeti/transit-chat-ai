import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../trafiklab/trafiklab_providers.dart';
import '../trafiklab/trafiklab_models.dart' as tl;
import 'package:latlong2/latlong.dart';

/// If set, we call the BFF /route. If empty, we fall back to OSRM demo.
const defaultRouteApiUrl = String.fromEnvironment('ROUTE_URL', defaultValue: '');
const _osrmBase = 'https://router.project-osrm.org/route/v1/driving';

class MapRouteLeg {
  MapRouteLeg({required this.mode, required this.points});
  final String mode;
  final List<LatLng> points;

  bool get isWalk => mode.toLowerCase().contains('walk');
}

class RouteQuery {
  RouteQuery({required this.origin, required this.destination});
  final LatLng origin;
  final LatLng destination;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RouteQuery &&
        origin.latitude == other.origin.latitude &&
        origin.longitude == other.origin.longitude &&
        destination.latitude == other.destination.latitude &&
        destination.longitude == other.destination.longitude;
  }

  @override
  int get hashCode => origin.latitude.hashCode ^ origin.longitude.hashCode ^ destination.latitude.hashCode ^ destination.longitude.hashCode;
}

Future<List<MapRouteLeg>> _callBff(RouteQuery query) async {
  if (defaultRouteApiUrl.isEmpty) throw Exception('No BFF route URL');
  final uri = Uri.parse(defaultRouteApiUrl);
  final body = {
    'origin': {'lat': query.origin.latitude, 'lon': query.origin.longitude},
    'destination': {'lat': query.destination.latitude, 'lon': query.destination.longitude},
    'arrive_by': false,
    'departure_time': DateTime.now().toIso8601String(),
  };

  final resp = await http.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body));
  // Debug routing call details
  // ignore: avoid_print
  print('[route] BFF url=$uri status=${resp.statusCode} body=${resp.body.substring(0, resp.body.length.clamp(0, 200))}');
  if (resp.statusCode >= 300) throw Exception('Routing failed ${resp.statusCode}: ${resp.body}');
  final data = jsonDecode(resp.body) as Map<String, dynamic>;
  final legs = (data['legs'] as List<dynamic>? ?? [])
      .map((raw) {
        final mode = (raw['mode'] ?? 'BUS').toString();
        final coords = (raw['geometry'] as List<dynamic>? ?? [])
            .map((p) => LatLng((p as List)[0] as double, (p)[1] as double))
            .toList();
        return MapRouteLeg(mode: mode, points: coords);
      })
      .where((leg) => leg.points.length >= 2)
      .toList();
  if (legs.isEmpty) throw Exception('Empty legs');
  return legs;
}

Future<List<MapRouteLeg>> _callOsrm(RouteQuery query) async {
  final url = '$_osrmBase/${query.origin.longitude},${query.origin.latitude};${query.destination.longitude},${query.destination.latitude}'
      '?overview=full&geometries=geojson';
  final uri = Uri.parse(url);
  final resp = await http.get(uri);
  // ignore: avoid_print
  print('[route] OSRM url=$uri status=${resp.statusCode} body=${resp.body.substring(0, resp.body.length.clamp(0, 200))}');
  if (resp.statusCode >= 300) throw Exception('OSRM failed ${resp.statusCode}: ${resp.body}');
  final data = jsonDecode(resp.body) as Map<String, dynamic>;
  final routes = data['routes'] as List<dynamic>? ?? [];
  if (routes.isEmpty) throw Exception('No routes');
  final geom = (routes.first as Map<String, dynamic>)['geometry'] as Map<String, dynamic>?;
  final coords = (geom?['coordinates'] as List<dynamic>? ?? [])
      .map((p) => LatLng((p as List)[1] as double, (p)[0] as double))
      .toList();
  if (coords.length < 2) throw Exception('Too few coords');
  // Mark as BUS to render solid; OSRM demo uses driving profile.
  return [MapRouteLeg(mode: 'BUS', points: coords)];
}

final mapRouteLegsProvider = FutureProvider.family<List<MapRouteLeg>, RouteQuery>((ref, query) async {
  // Prefer a TrafikLab planTrip if an API key is configured.
  final api = ref.watch(trafiklabApiProvider);
  final repo = ref.watch(trafiklabRepositoryProvider);
  if ((api.apiKey).isNotEmpty) {
    try {
      final plan = await repo.planTrip(query.origin, query.destination);
      final legs = plan.legs
          .map((l) => MapRouteLeg(mode: l.mode, points: l.points))
          .where((leg) => leg.points.length >= 2)
          .toList();
      if (legs.isNotEmpty) return legs;
    } catch (_) {}
  }

  if (defaultRouteApiUrl.isNotEmpty) {
    return await _callBff(query);
  }

  // No BFF and no TrafikLab plan available, use OSRM; if OSRM fails, surface the error.
  return await _callOsrm(query);
});
