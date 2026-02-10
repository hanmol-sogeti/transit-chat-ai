import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class GtfsDatabase {
  static const _dbName = 'gtfs_ul.db';
  static const _dbVersion = 1;

  Database? _db;

  bool _memoryInitialized = false;
  final Map<String, List<Map<String, Object?>>> _memoryTables = {
    'stops': <Map<String, Object?>>[],
    'routes': <Map<String, Object?>>[],
    'trips': <Map<String, Object?>>[],
    'stop_times': <Map<String, Object?>>[],
    'shapes': <Map<String, Object?>>[],
  };

  Future<Database> database() async {
    if (kIsWeb) {
      throw UnsupportedError('SQLite database is not available on Flutter web for this demo.');
    }
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, _dbName);
    _db = await openDatabase(dbPath, version: _dbVersion, onCreate: _onCreate);
    return _db!;
  }

  void _ensureMemorySeeded() {
    if (_memoryInitialized) return;
    _memoryInitialized = true;
    _memoryTables.forEach((key, value) => value.clear());

    _memoryTables['stops']!.addAll([
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
    ]);

    _memoryTables['routes']!.add({
      'route_id': 'UL101',
      'route_short_name': '101',
      'route_long_name': 'Uppsala - Central - Gränby',
    });

    _memoryTables['trips']!.add({
      'trip_id': 'UL101_AM',
      'route_id': 'UL101',
      'service_id': 'WEEKDAY',
      'trip_headsign': 'Gränby',
    });

    final now = DateTime.now();
    final departures = [10, 25, 40];
    for (final offset in departures) {
      final time = now.add(Duration(minutes: offset));
      _memoryTables['stop_times']!.addAll([
        {'trip_id': 'UL101_AM', 'stop_id': '7500', 'arrival_time': time.toIso8601String()},
        {
          'trip_id': 'UL101_AM',
          'stop_id': '7501',
          'arrival_time': time.add(const Duration(minutes: 7)).toIso8601String(),
        },
        {
          'trip_id': 'UL101_AM',
          'stop_id': '7502',
          'arrival_time': time.add(const Duration(minutes: 15)).toIso8601String(),
        },
      ]);
    }

    final shapePoints = [
      {'lat': 59.8586, 'lon': 17.6454, 'seq': 0},
      {'lat': 59.8600, 'lon': 17.6400, 'seq': 1},
      {'lat': 59.8630, 'lon': 17.6350, 'seq': 2},
      {'lat': 59.8675, 'lon': 17.6420, 'seq': 3},
      {'lat': 59.8741, 'lon': 17.6707, 'seq': 4},
    ];
    for (final pt in shapePoints) {
      _memoryTables['shapes']!.add({
        'shape_id': 'UL101',
        'shape_pt_lat': pt['lat'],
        'shape_pt_lon': pt['lon'],
        'shape_pt_sequence': pt['seq'],
      });
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE stops (
        stop_id TEXT PRIMARY KEY,
        stop_name TEXT,
        stop_lat REAL,
        stop_lon REAL
      );
    ''');
    await db.execute('''
      CREATE TABLE routes (
        route_id TEXT PRIMARY KEY,
        route_short_name TEXT,
        route_long_name TEXT
      );
    ''');
    await db.execute('''
      CREATE TABLE trips (
        trip_id TEXT PRIMARY KEY,
        route_id TEXT,
        service_id TEXT,
        trip_headsign TEXT
      );
    ''');
    await db.execute('''
      CREATE TABLE stop_times (
        trip_id TEXT,
        stop_id TEXT,
        arrival_time TEXT
      );
    ''');
    await db.execute('''
      CREATE TABLE shapes (
        shape_id TEXT,
        shape_pt_lat REAL,
        shape_pt_lon REAL,
        shape_pt_sequence INTEGER
      );
    ''');
    await _seedSample(db);
  }

  Future<void> _seedSample(DatabaseExecutor db) async {
    await db.insert('stops', {
      'stop_id': '7500',
      'stop_name': 'Uppsala Centralstation',
      'stop_lat': 59.8586,
      'stop_lon': 17.6454,
    });
    await db.insert('stops', {
      'stop_id': '7501',
      'stop_name': 'Uppsala Universitetet',
      'stop_lat': 59.8583,
      'stop_lon': 17.6296,
    });
    await db.insert('stops', {
      'stop_id': '7502',
      'stop_name': 'Gränby Centrum',
      'stop_lat': 59.8741,
      'stop_lon': 17.6707,
    });
    await db.insert('stops', {
      'stop_id': '7503',
      'stop_name': 'Bredgränd 14',
      'stop_lat': 59.8580,
      'stop_lon': 17.6389,
    });
    await db.insert('stops', {
      'stop_id': '7504',
      'stop_name': 'Börjetull',
      'stop_lat': 59.8725,
      'stop_lon': 17.6150,
    });

    await db.insert('routes', {
      'route_id': 'UL101',
      'route_short_name': '101',
      'route_long_name': 'Uppsala - Central - Gränby',
    });

    await db.insert('trips', {
      'trip_id': 'UL101_AM',
      'route_id': 'UL101',
      'service_id': 'WEEKDAY',
      'trip_headsign': 'Gränby',
    });

    final now = DateTime.now();
    final departures = [10, 25, 40];
    for (final offset in departures) {
      final time = now.add(Duration(minutes: offset));
      final formatted = time.toIso8601String();
      await db.insert('stop_times', {'trip_id': 'UL101_AM', 'stop_id': '7500', 'arrival_time': formatted});
      await db.insert('stop_times', {'trip_id': 'UL101_AM', 'stop_id': '7501', 'arrival_time': time.add(const Duration(minutes: 7)).toIso8601String()});
      await db.insert('stop_times', {'trip_id': 'UL101_AM', 'stop_id': '7502', 'arrival_time': time.add(const Duration(minutes: 15)).toIso8601String()});
    }

    final shapePoints = [
      {'lat': 59.8586, 'lon': 17.6454, 'seq': 0},
      {'lat': 59.8600, 'lon': 17.6400, 'seq': 1},
      {'lat': 59.8630, 'lon': 17.6350, 'seq': 2},
      {'lat': 59.8675, 'lon': 17.6420, 'seq': 3},
      {'lat': 59.8741, 'lon': 17.6707, 'seq': 4},
      {'lat': 59.8580, 'lon': 17.6389, 'seq': 5},
      {'lat': 59.8725, 'lon': 17.6150, 'seq': 6},
    ];
    for (final p in shapePoints) {
      await db.insert('shapes', {
        'shape_id': 'UL101',
        'shape_pt_lat': p['lat'],
        'shape_pt_lon': p['lon'],
        'shape_pt_sequence': p['seq'],
      });
    }
  }

  Future<List<Map<String, Object?>>> query(String table) async {
    if (kIsWeb) {
      _ensureMemorySeeded();
      return List<Map<String, Object?>>.from(_memoryTables[table] ?? const []);
    }
    final db = await database();
    return db.query(table);
  }

  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? args]) async {
    if (kIsWeb) {
      _ensureMemorySeeded();
      final normalized = sql.toLowerCase();

      if (normalized.contains('from shapes') && normalized.contains('where shape_id')) {
        final shapeId = (args != null && args.isNotEmpty) ? args.first?.toString() : null;
        final rows = (_memoryTables['shapes'] ?? const [])
            .where((r) => shapeId == null || r['shape_id']?.toString() == shapeId)
            .toList();
        rows.sort((a, b) => ((a['shape_pt_sequence'] as num?) ?? 0).compareTo(((b['shape_pt_sequence'] as num?) ?? 0)));
        return rows
            .map((r) => {
                  'shape_pt_lat': r['shape_pt_lat'],
                  'shape_pt_lon': r['shape_pt_lon'],
                  'shape_pt_sequence': r['shape_pt_sequence'],
                })
            .toList();
      }

      if (normalized.contains('from stop_times') && normalized.contains('where st.stop_id')) {
        final stopId = (args != null && args.isNotEmpty) ? args.first?.toString() : null;
        final stopTimes = (_memoryTables['stop_times'] ?? const [])
            .where((r) => stopId == null || r['stop_id']?.toString() == stopId)
            .toList();

        stopTimes.sort((a, b) => (a['arrival_time']?.toString() ?? '').compareTo(b['arrival_time']?.toString() ?? ''));
        final limited = stopTimes.take(20).toList();

        final stopsById = {for (final s in (_memoryTables['stops'] ?? const [])) s['stop_id']?.toString(): s};
        final tripsById = {for (final t in (_memoryTables['trips'] ?? const [])) t['trip_id']?.toString(): t};
        final routesById = {for (final r in (_memoryTables['routes'] ?? const [])) r['route_id']?.toString(): r};

        final out = <Map<String, Object?>>[];
        for (final st in limited) {
          final trip = tripsById[st['trip_id']?.toString()];
          final route = routesById[trip?['route_id']?.toString()];
          final stop = stopsById[st['stop_id']?.toString()];
          out.add({
            'trip_id': st['trip_id'],
            'arrival_time': st['arrival_time'],
            'route_id': trip?['route_id'],
            'trip_headsign': trip?['trip_headsign'],
            'route_short_name': route?['route_short_name'],
            'route_long_name': route?['route_long_name'],
            'stop_id': stop?['stop_id'],
            'stop_name': stop?['stop_name'],
            'stop_lat': stop?['stop_lat'],
            'stop_lon': stop?['stop_lon'],
          });
        }
        return out;
      }

      throw UnsupportedError('Unsupported in-memory SQL on web: $sql');
    }

    final db = await database();
    return db.rawQuery(sql, args);
  }

  Future<void> clearAndSeed() async {
    if (kIsWeb) {
      _memoryInitialized = false;
      _ensureMemorySeeded();
      return;
    }
    final db = await database();
    await db.transaction((txn) async {
      await txn.delete('stop_times');
      await txn.delete('trips');
      await txn.delete('routes');
      await txn.delete('stops');
      await txn.delete('shapes');
      await _seedSample(txn);
    });
  }
}
