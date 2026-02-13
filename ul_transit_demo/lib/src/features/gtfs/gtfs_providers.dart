import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'gtfs_database.dart';
import 'gtfs_models.dart';
import 'gtfs_repository.dart';
import '../trafiklab/trafiklab_providers.dart';


final gtfsDatabaseProvider = Provider((ref) => GtfsDatabase());
final gtfsRepositoryProvider = Provider((ref) => GtfsRepository(ref.read(gtfsDatabaseProvider)));

final stopsProvider = FutureProvider<List<Stop>>((ref) async {
  // Prefer TrafikLab repository when configured; otherwise fall back to local GTFS.
  final api = ref.watch(trafiklabApiProvider);
  if ((api.apiKey).isNotEmpty) {
    final repo = ref.watch(trafiklabRepositoryProvider);
    try {
      return await repo.searchStops('');
    } catch (_) {}
  }
  return await ref.read(gtfsRepositoryProvider).listStops();
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
    // If TrafikLab is configured, ask the TrafikLab repository for nearest stops
    final api = ref.watch(trafiklabApiProvider);
    if ((api.apiKey).isNotEmpty) {
      final repo = ref.watch(trafiklabRepositoryProvider);
      try {
        return await repo.nearestStops(user, limit: 10);
      } catch (_) {}
    }
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

final stopDeparturesProvider = FutureProvider.family<List<Departure>, String>((ref, stopId) async {
  final api = ref.watch(trafiklabApiProvider);
  if ((api.apiKey).isNotEmpty) {
    final repo = ref.watch(trafiklabRepositoryProvider);
    try {
      return await repo.departuresForStop(stopId);
    } catch (_) {}
  }
  return await ref.read(gtfsRepositoryProvider).departuresForStop(stopId);
});

final shapeProvider = FutureProvider.family<List<ShapePoint>, String>((ref, shapeId) async {
  // Shapes are provided by local GTFS data; TrafikLab may not have shape points.
  return await ref.read(gtfsRepositoryProvider).shapePoints(shapeId);
});
