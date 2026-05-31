import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:betracky_background_location/models/location.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  static Database? _database;

  DatabaseHelper._internal();

  /// Closes, deletes, and resets the database. For use in tests only.
  @visibleForTesting
  static Future<void> resetForTesting() async {
    final db = _database;
    _database = null;
    await db?.close();
    try {
      final path = join(await getDatabasesPath(), 'locations.db');
      await deleteDatabase(path);
    } catch (_) {}
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final path = join(await getDatabasesPath(), 'locations.db');
    return openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE locations(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        latitude REAL,
        longitude REAL,
        altitude REAL,
        speed REAL,
        heading REAL,
        accuracy REAL,
        timestamp TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE pending_uploads(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        payload TEXT NOT NULL,
        url TEXT NOT NULL,
        access_token TEXT,
        custom_headers TEXT,
        attempts INTEGER DEFAULT 0,
        next_retry_at TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE locations ADD COLUMN altitude REAL');
      await db.execute('ALTER TABLE locations ADD COLUMN speed REAL');
      await db.execute('ALTER TABLE locations ADD COLUMN heading REAL');
      await db.execute('ALTER TABLE locations ADD COLUMN accuracy REAL');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS pending_uploads(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          payload TEXT NOT NULL,
          url TEXT NOT NULL,
          access_token TEXT,
          custom_headers TEXT,
          attempts INTEGER DEFAULT 0,
          next_retry_at TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
    }
  }

  // ─── Location CRUD ────────────────────────────────────────────────────────

  Future<void> insertLocation(LocationDataModel location) async {
    final db = await database;
    await db.insert(
      'locations',
      location.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<LocationDataModel>> getBatchLocation(int limit) async {
    final db = await database;
    final maps = await db.query('locations', limit: limit, orderBy: 'id ASC');
    return maps.map(_rowToLocation).toList();
  }

  Future<List<LocationDataModel>> getLocationsByDateRange({
    DateTime? from,
    DateTime? to,
    int limit = 500,
  }) async {
    final db = await database;
    String? where;
    List<Object?>? whereArgs;

    if (from != null && to != null) {
      where = 'timestamp >= ? AND timestamp <= ?';
      whereArgs = [from.toIso8601String(), to.toIso8601String()];
    } else if (from != null) {
      where = 'timestamp >= ?';
      whereArgs = [from.toIso8601String()];
    } else if (to != null) {
      where = 'timestamp <= ?';
      whereArgs = [to.toIso8601String()];
    }

    final maps = await db.query(
      'locations',
      where: where,
      whereArgs: whereArgs,
      limit: limit,
      orderBy: 'timestamp ASC',
    );
    return maps.map(_rowToLocation).toList();
  }

  Future<int> countLocations() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM locations');
    return (result.first['count'] as int?) ?? 0;
  }

  Future<void> deleteBatchLocations(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    try {
      final placeholders = ids.map((_) => '?').join(',');
      await db.delete(
        'locations',
        where: 'id IN ($placeholders)',
        whereArgs: ids,
      );
    } catch (e) {
      debugPrint('BeTracky DB delete error: $e');
    }
  }

  Future<void> clearLocations() async {
    final db = await database;
    await db.delete('locations');
  }

  LocationDataModel _rowToLocation(Map<String, dynamic> m) {
    return LocationDataModel(
      id: m['id'] as int?,
      latitude: m['latitude'] as double,
      longitude: m['longitude'] as double,
      altitude: m['altitude'] as double?,
      speed: m['speed'] as double?,
      heading: m['heading'] as double?,
      accuracy: m['accuracy'] as double?,
      timestamp: DateTime.parse(m['timestamp'] as String),
    );
  }

  // ─── Pending Uploads (Retry Queue) ────────────────────────────────────────

  Future<void> insertPendingUpload({
    required String payload,
    required String url,
    String? accessToken,
    Map<String, String>? customHeaders,
  }) async {
    final db = await database;
    final now = DateTime.now();
    await db.insert('pending_uploads', {
      'payload': payload,
      'url': url,
      'access_token': accessToken,
      'custom_headers': customHeaders != null ? jsonEncode(customHeaders) : null,
      'attempts': 0,
      'next_retry_at': now.add(const Duration(minutes: 1)).toIso8601String(),
      'created_at': now.toIso8601String(),
    });
  }

  /// Returns pending uploads whose next_retry_at <= [now] and attempts < [maxRetries].
  Future<List<Map<String, dynamic>>> getPendingUploads(
    DateTime now,
    int maxRetries,
  ) async {
    final db = await database;
    return db.query(
      'pending_uploads',
      where: 'next_retry_at <= ? AND attempts < ?',
      whereArgs: [now.toIso8601String(), maxRetries],
      orderBy: 'created_at ASC',
    );
  }

  Future<void> deletePendingUpload(int id) async {
    final db = await database;
    await db.delete('pending_uploads', where: 'id = ?', whereArgs: [id]);
  }

  /// Increments retry count and schedules next attempt using exponential backoff.
  /// Deletes the record if [currentAttempts] + 1 >= [maxRetries].
  Future<void> incrementRetryAttempt(
    int id,
    int currentAttempts,
    int maxRetries,
  ) async {
    final newAttempts = currentAttempts + 1;
    if (newAttempts >= maxRetries) {
      await deletePendingUpload(id);
      return;
    }
    final delayMinutes = math.min(60, math.pow(2, newAttempts).toInt());
    final nextRetryAt = DateTime.now().add(Duration(minutes: delayMinutes));
    final db = await database;
    await db.update(
      'pending_uploads',
      {
        'attempts': newAttempts,
        'next_retry_at': nextRetryAt.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> countPendingUploads() async {
    final db = await database;
    final result =
        await db.rawQuery('SELECT COUNT(*) as count FROM pending_uploads');
    return (result.first['count'] as int?) ?? 0;
  }
}
