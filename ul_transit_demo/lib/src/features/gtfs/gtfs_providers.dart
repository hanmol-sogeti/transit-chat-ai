import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'gtfs_database.dart';
import 'gtfs_models.dart';
import 'gtfs_repository.dart';

final gtfsDatabaseProvider = Provider((ref) => GtfsDatabase());
final gtfsRepositoryProvider = Provider((ref) => GtfsRepository(ref.read(gtfsDatabaseProvider)));

final stopsProvider = FutureProvider<List<Stop>>((ref) async {
  // Use the local GTFS repository only; avoid fetching from a backend service.
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
