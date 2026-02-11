import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'gtfs_database.dart';
import 'gtfs_models.dart';
import 'gtfs_repository.dart';

const defaultStopsApiUrl = String.fromEnvironment('STOPS_URL', defaultValue: 'http://localhost:8001/stops');

final gtfsDatabaseProvider = Provider((ref) => GtfsDatabase());
final gtfsRepositoryProvider = Provider((ref) => GtfsRepository(ref.read(gtfsDatabaseProvider)));

Future<List<Stop>> _fetchStopsFromBff() async {
  if (defaultStopsApiUrl.isEmpty) throw Exception('No stops URL configured');
  final uri = Uri.parse(defaultStopsApiUrl);
  final resp = await http.get(uri);
  if (resp.statusCode >= 300) {
    throw Exception('Stops fetch failed ${resp.statusCode}: ${resp.body}');
  }
  final data = jsonDecode(resp.body) as List<dynamic>;
  return data
      .map((e) => Stop(
            id: (e['id'] ?? '').toString(),
            name: (e['name'] ?? '').toString(),
            lat: (e['lat'] as num).toDouble(),
            lon: (e['lon'] as num).toDouble(),
          ))
      .toList();
}

final stopsProvider = FutureProvider<List<Stop>>((ref) async {
  try {
    final stops = await _fetchStopsFromBff();
    if (stops.isNotEmpty) return stops;
  } catch (_) {
    // Ignore and fall back to local DB.
  }
  return ref.read(gtfsRepositoryProvider).listStops();
});

final nearestStopsProvider = FutureProvider.autoDispose<List<Stop>>((ref) async {
  final stops = await ref.watch(stopsProvider.future);
  try {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }
    final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    final user = LatLng(position.latitude, position.longitude);
    final sorted = [...stops];
    final dist = const Distance();
    sorted.sort((a, b) {
      final da = dist(user, LatLng(a.lat, a.lon));
      final db = dist(user, LatLng(b.lat, b.lon));
      return da.compareTo(db);
    });
    return sorted.take(10).toList();
  } catch (_) {
    // Fallback: return stops as-is when location unavailable.
    return stops;
  }
});

final stopDeparturesProvider = FutureProvider.family<List<Departure>, String>((ref, stopId) {
  return ref.read(gtfsRepositoryProvider).departuresForStop(stopId);
});

final shapeProvider = FutureProvider.family<List<ShapePoint>, String>((ref, shapeId) {
  return ref.read(gtfsRepositoryProvider).shapePoints(shapeId);
});
