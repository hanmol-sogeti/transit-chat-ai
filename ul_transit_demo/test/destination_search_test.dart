import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:ul_transit_demo/src/features/chat/chat_screen.dart';
import 'package:ul_transit_demo/src/features/gtfs/gtfs_models.dart';

void main() {
  group('searchStopsByAreaForTest', () {
    test('prioritizes stops inside geocoded bbox (Flogsta)', () async {
      final stops = <Stop>[
        Stop(id: '1', name: 'Flogsta centrum', lat: 59.8469, lon: 17.5899),
        Stop(id: '2', name: 'Ekonomikum', lat: 59.8587, lon: 17.6298),
        Stop(id: '3', name: 'Centralstation', lat: 59.8586, lon: 17.6389),
      ];

      Future<GeoArea?> stubGeocode(String _) async {
        return const GeoArea(
          south: 59.844,
          north: 59.850,
          west: 17.584,
          east: 17.595,
          center: LatLng(59.8469, 17.5899),
        );
      }

      final result = await searchStopsByAreaForTest('Flogsta', stops, geocodeFn: stubGeocode);

      expect(result, isNotEmpty);
      expect(result.first.name, contains('Flogsta'));
      expect(result.any((s) => s.name.contains('Flogsta')), isTrue);
    });

    test('includes polygon-contained stop even if outside bbox', () async {
      final stops = <Stop>[
        Stop(id: 'poly', name: 'Polygon Stop', lat: 2.005, lon: 2.005),
        Stop(id: 'box', name: 'Box Stop', lat: 0.5, lon: 0.5),
      ];

      Future<GeoArea?> stubGeocode(String _) async {
        return GeoArea(
          south: 0,
          north: 1,
          west: 0,
          east: 1,
          center: const LatLng(0.5, 0.5),
          polygon: const [
            LatLng(2.0, 2.0),
            LatLng(2.01, 2.0),
            LatLng(2.01, 2.01),
            LatLng(2.0, 2.01),
          ],
        );
      }

      final result = await searchStopsByAreaForTest('Polygon', stops, geocodeFn: stubGeocode);

      expect(result.any((s) => s.id == 'poly'), isTrue);
      expect(result.first.id, 'poly');
    });

    test('applies radius gate inside bbox', () async {
      final stops = <Stop>[
        Stop(id: 'near', name: 'Near Center', lat: 59.0003, lon: 17.0),
        Stop(id: 'far', name: 'Far Center', lat: 59.0020, lon: 17.0),
      ];

      Future<GeoArea?> stubGeocode(String _) async {
        return GeoArea(
          south: 58.9,
          north: 59.1,
          west: 16.9,
          east: 17.1,
          center: const LatLng(59.0, 17.0),
          radiusMeters: 50, // ~50 m radius
        );
      }

      final result = await searchStopsByAreaForTest('Radius', stops, geocodeFn: stubGeocode);

      expect(result.any((s) => s.id == 'near'), isTrue);
      expect(result.any((s) => s.id == 'far'), isFalse);
    });

    test('real geocode returns Flogsta area (network)', () async {
      final stops = <Stop>[
        Stop(id: '1', name: 'Flogsta centrum', lat: 59.8469, lon: 17.5899),
        Stop(id: '2', name: 'Ekonomikum', lat: 59.8587, lon: 17.6298),
      ];

      // This uses the real geocoder (_geocodeArea) and therefore requires network.
      final result = await searchStopsByAreaForTest('Flogsta', stops);

      expect(result, isNotEmpty);
      expect(result.any((s) => s.name.toLowerCase().contains('flogsta')), isTrue);
    });

    test('exists stop within Flogsta area (network)', () async {
      final stops = <Stop>[
        // A stop known to be inside Flogsta
        Stop(id: 'fl1', name: 'Flogsta centrum', lat: 59.8469, lon: 17.5899),
        // Nearby but outside sample
        Stop(id: 'o1', name: 'Outside', lat: 59.8700, lon: 17.6500),
      ];

      final result = await searchStopsByAreaForTest('Flogsta', stops);

      expect(result, isNotEmpty);
      // At least one returned stop must be one of our sample stops within Flogsta
      expect(result.any((s) => s.id == 'fl1'), isTrue);
    });
  });
}
