import 'dart:async';
import 'dart:convert';

import 'package:archive/archive_io.dart';
import 'package:csv/csv.dart';
import 'package:latlong2/latlong.dart';

import 'gtfs_database.dart';
import 'gtfs_models.dart';

class GtfsRepository {
  GtfsRepository(this._db);

  final GtfsDatabase _db;
  final _distance = const Distance();

  Future<List<Stop>> listStops() async {
    final rows = await _db.query('stops');
    return rows
        .map((e) => Stop(
              id: e['stop_id'] as String,
              name: e['stop_name'] as String,
              lat: (e['stop_lat'] as num).toDouble(),
              lon: (e['stop_lon'] as num).toDouble(),
            ))
        .toList();
  }

  Future<List<Stop>> nearestStops(LatLng user, {int limit = 10}) async {
    final stops = await listStops();
    stops.sort((a, b) {
      final da = _distance(user, LatLng(a.lat, a.lon));
      final db = _distance(user, LatLng(b.lat, b.lon));
      return da.compareTo(db);
    });
    return stops.take(limit).toList();
  }

  Future<List<Departure>> departuresForStop(String stopId) async {
    final rows = await _db.rawQuery('''
      SELECT st.trip_id, st.arrival_time, t.route_id, t.trip_headsign, r.route_short_name, r.route_long_name, s.stop_id, s.stop_name, s.stop_lat, s.stop_lon
      FROM stop_times st
      JOIN trips t ON t.trip_id = st.trip_id
      JOIN routes r ON r.route_id = t.route_id
      JOIN stops s ON s.stop_id = st.stop_id
      WHERE st.stop_id = ?
      ORDER BY st.arrival_time ASC
      LIMIT 20;
    ''', [stopId]);

    return rows
        .map((row) => Departure(
              trip: TripInfo(
                id: row['trip_id'] as String,
                routeId: row['route_id'] as String,
                serviceId: 'WEEKDAY',
                headsign: (row['trip_headsign'] ?? '') as String,
              ),
              route: RouteInfo(
                id: row['route_id'] as String,
                shortName: (row['route_short_name'] ?? '') as String,
                longName: (row['route_long_name'] ?? '') as String,
              ),
              arrivalTime: DateTime.parse(row['arrival_time'] as String),
              stop: Stop(
                id: row['stop_id'] as String,
                name: row['stop_name'] as String,
                lat: (row['stop_lat'] as num).toDouble(),
                lon: (row['stop_lon'] as num).toDouble(),
              ),
            ))
        .toList();
  }

  Future<List<ShapePoint>> shapePoints(String shapeId) async {
    final rows = await _db.rawQuery('''
      SELECT shape_pt_lat, shape_pt_lon, shape_pt_sequence FROM shapes WHERE shape_id = ? ORDER BY shape_pt_sequence ASC;
    ''', [shapeId]);
    return rows
        .map((row) => ShapePoint(
              shapeId: shapeId,
              lat: (row['shape_pt_lat'] as num).toDouble(),
              lon: (row['shape_pt_lon'] as num).toDouble(),
              sequence: (row['shape_pt_sequence'] as num).toInt(),
            ))
        .toList();
  }

  Future<void> importGtfsZip(String zipPath) async {
    final input = InputFileStream(zipPath);
    final archive = ZipDecoder().decodeBuffer(input);
    final tables = <String, List<List<dynamic>>>{};

    for (final file in archive) {
      final name = file.name.toLowerCase();
      if (!name.endsWith('.txt')) continue;
      final content = utf8.decode(file.content as List<int>);
      final rows = const CsvToListConverter(eol: '\n').convert(content, shouldParseNumbers: false);
      tables[name] = rows;
    }

    final db = await _db.database();
    await db.transaction((txn) async {
      await txn.delete('stop_times');
      await txn.delete('trips');
      await txn.delete('routes');
      await txn.delete('stops');
      await txn.delete('shapes');

      final stops = tables['stops.txt'] ?? [];
      if (stops.isNotEmpty) {
        final headers = stops.first;
        for (final row in stops.skip(1)) {
          final map = _rowToMap(headers, row);
          await txn.insert('stops', {
            'stop_id': map['stop_id'],
            'stop_name': map['stop_name'],
            'stop_lat': double.tryParse(map['stop_lat'] ?? '') ?? 0,
            'stop_lon': double.tryParse(map['stop_lon'] ?? '') ?? 0,
          });
        }
      }

      final routes = tables['routes.txt'] ?? [];
      if (routes.isNotEmpty) {
        final headers = routes.first;
        for (final row in routes.skip(1)) {
          final map = _rowToMap(headers, row);
          await txn.insert('routes', {
            'route_id': map['route_id'],
            'route_short_name': map['route_short_name'],
            'route_long_name': map['route_long_name'],
          });
        }
      }

      final trips = tables['trips.txt'] ?? [];
      if (trips.isNotEmpty) {
        final headers = trips.first;
        for (final row in trips.skip(1)) {
          final map = _rowToMap(headers, row);
          await txn.insert('trips', {
            'trip_id': map['trip_id'],
            'route_id': map['route_id'],
            'service_id': map['service_id'],
            'trip_headsign': map['trip_headsign'],
          });
        }
      }

      final stopTimes = tables['stop_times.txt'] ?? [];
      if (stopTimes.isNotEmpty) {
        final headers = stopTimes.first;
        for (final row in stopTimes.skip(1)) {
          final map = _rowToMap(headers, row);
          final arrival = map['arrival_time'] ?? map['departure_time'] ?? '';
          await txn.insert('stop_times', {
            'trip_id': map['trip_id'],
            'stop_id': map['stop_id'],
            'arrival_time': arrival,
          });
        }
      }

      final shapes = tables['shapes.txt'] ?? [];
      if (shapes.isNotEmpty) {
        final headers = shapes.first;
        for (final row in shapes.skip(1)) {
          final map = _rowToMap(headers, row);
          await txn.insert('shapes', {
            'shape_id': map['shape_id'],
            'shape_pt_lat': double.tryParse(map['shape_pt_lat'] ?? '') ?? 0,
            'shape_pt_lon': double.tryParse(map['shape_pt_lon'] ?? '') ?? 0,
            'shape_pt_sequence': int.tryParse(map['shape_pt_sequence'] ?? '0') ?? 0,
          });
        }
      }
    });
  }

  Map<String, String> _rowToMap(List<dynamic> headers, List<dynamic> row) {
    final map = <String, String>{};
    for (var i = 0; i < headers.length && i < row.length; i++) {
      map[headers[i].toString()] = row[i].toString();
    }
    return map;
  }
}
