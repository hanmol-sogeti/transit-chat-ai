import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'gtfs_database.dart';
import 'gtfs_models.dart';
import 'gtfs_repository.dart';

final gtfsDatabaseProvider = Provider((ref) => GtfsDatabase());
final gtfsRepositoryProvider = Provider((ref) => GtfsRepository(ref.read(gtfsDatabaseProvider)));

final stopsProvider = FutureProvider<List<Stop>>((ref) {
  return ref.read(gtfsRepositoryProvider).listStops();
});

final nearestStopsProvider = FutureProvider.autoDispose<List<Stop>>((ref) async {
  try {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }
    final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    final user = LatLng(position.latitude, position.longitude);
    return ref.read(gtfsRepositoryProvider).nearestStops(user);
  } catch (_) {
    // Fallback: return first stops when location unavailable.
    return ref.read(gtfsRepositoryProvider).listStops();
  }
});

final stopDeparturesProvider = FutureProvider.family<List<Departure>, String>((ref, stopId) {
  return ref.read(gtfsRepositoryProvider).departuresForStop(stopId);
});

final shapeProvider = FutureProvider.family<List<ShapePoint>, String>((ref, shapeId) {
  return ref.read(gtfsRepositoryProvider).shapePoints(shapeId);
});
