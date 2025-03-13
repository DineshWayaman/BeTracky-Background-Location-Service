import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:betracky_background_location/models/location.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper.internal();
  factory DatabaseHelper() => _instance;
  static Database? _database;

  DatabaseHelper.internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    String path = join(await getDatabasesPath(), 'locations.db');
    return await openDatabase(path, version: 1, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE locations(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        latitude REAL,
        longitude REAL,
        timestamp TEXT
      )
    ''');
  }

  Future<void> insertLocation(LocationDataModel location) async {
    final db = await database;
    await db.insert(
      'locations',
      location.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    print('Location data saved to local database.');
  }

  Future<List<LocationDataModel>> getLocations() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('locations');
    return List.generate(maps.length, (i) {
      return LocationDataModel(
        latitude: maps[i]['latitude'],
        longitude: maps[i]['longitude'],
        timestamp: DateTime.parse(maps[i]['timestamp']),
      );
    });
  }

  Future<List<LocationDataModel>> getBatchLocation(int limit) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'locations',
      limit: limit,
    );
    return List.generate(maps.length, (i) {
      return LocationDataModel(
        id: maps[i]['id'],
        latitude: maps[i]['latitude'],
        longitude: maps[i]['longitude'],
        timestamp: DateTime.parse(maps[i]['timestamp']),
      );
    });
  }

  Future<void> deleteBatchLocations(List<int> ids) async {
    print("DeleteL ${ids.length}");
    final db = await database;
    try {
      final idList = ids.join(',');
      await db.delete(
        'locations',
        where: 'id IN ($idList)',
      );
      print('Data Deleted Successfully:');
    } catch (e) {
      print('ErrorDeleting: $e');
    }
  }
}
