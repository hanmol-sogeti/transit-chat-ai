import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:ul_transit_demo/src/features/gtfs/gtfs_repository.dart';
import 'package:ul_transit_demo/src/features/map/map_route_provider.dart';

// A small test double that overrides only the methods used by the
// GtfsRepository in these unit tests.
import 'package:ul_transit_demo/src/features/gtfs/gtfs_database.dart';

class TestGtfsDb extends GtfsDatabase {
  final List<Map<String, Object?>> stops;
  TestGtfsDb(this.stops);

  @override
  Future<List<Map<String, Object?>>> query(String table) async {
    if (table == 'stops') return stops;
    return <Map<String, Object?>>[];
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? args]) async => <Map<String, Object?>>[];
}

void main() {
  group('GTFS nearest stop', () {
    late GtfsRepository repo;

    setUp(() {
      final stops = [
        {
          'stop_id': '7500',
          'stop_name': 'Uppsala Centralstation',
          'stop_lat': 59.8586,
          'stop_lon': 17.6454,
        },
        {
          'stop_id': '7501',
          'stop_name': 'Uppsala Universitetet',
          'stop_lat': 59.8583,
          'stop_lon': 17.6296,
        },
        {
          'stop_id': '7502',
          'stop_name': 'Gränby Centrum',
          'stop_lat': 59.8741,
          'stop_lon': 17.6707,
        },
        {
          'stop_id': '7503',
          'stop_name': 'Bredgränd 14',
          'stop_lat': 59.8580,
          'stop_lon': 17.6389,
        },
        {
          'stop_id': '7505',
          'stop_name': 'Flogsta',
          'stop_lat': 59.8469,
          'stop_lon': 17.5899,
        },
      ];

      final db = TestGtfsDb(stops);
      // GtfsRepository expects a `GtfsDatabase` instance; our test double
      // extends `GtfsDatabase` and overrides the query/rawQuery methods.
      repo = GtfsRepository(db);
    });

    test('nearest to Flogsta coords is Flogsta', () async {
      final near = await repo.nearestStops(LatLng(59.8469, 17.5899), limit: 1);
      expect(near, isNotEmpty);
      expect(near.first.id, '7505');
    });

    test('nearest to Bredgränd 14 coords is Bredgränd', () async {
      final near = await repo.nearestStops(LatLng(59.8580, 17.6389), limit: 1);
      expect(near, isNotEmpty);
      expect(near.first.id, '7503');
    });
  });

  group('MapRouteRequest parsing', () {
    test('parses English "from ... to ..."', () {
      final req = MapRouteRequest.fromText('Plan a trip from Bredgränd 14 to Flogsta');
      expect(req.origin?.toLowerCase().contains('bredgränd 14'), isTrue);
      expect(req.destination.toLowerCase().contains('flogsta'), isTrue);
    });

    test('parses Swedish "från ... till ..."', () {
      final req = MapRouteRequest.fromText('Planera resa från Bredgränd 14 till Flogsta');
      expect(req.origin?.toLowerCase().contains('bredgränd 14'), isTrue);
      expect(req.destination.toLowerCase().contains('flogsta'), isTrue);
    });

    test('defaults when text does not contain a route', () {
      final req = MapRouteRequest.fromText('Hello world');
      expect(req.origin, isNotNull);
      expect(req.destination, isNotNull);
    });
  });
}
