import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class GtfsDatabase {
  static const _dbName = 'gtfs_ul.db';
  static const _dbVersion = 1;

  Database? _db;

  Future<Database> database() async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, _dbName);
    _db = await openDatabase(dbPath, version: _dbVersion, onCreate: _onCreate);
    return _db!;
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
    final db = await database();
    return db.query(table);
  }

  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? args]) async {
    final db = await database();
    return db.rawQuery(sql, args);
  }

  Future<void> clearAndSeed() async {
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
