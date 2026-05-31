import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:betracky_background_location/betracky_background_location.dart';
import 'package:betracky_background_location/utils/database_helper.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  // Use FFI SQLite so database tests run without a device.
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    // Reset the singleton so every test group gets a fresh schema.
    await DatabaseHelper.resetForTesting();
  });

  // ─── LocationDataModel ─────────────────────────────────────────────────────

  group('LocationDataModel', () {
    final t = DateTime(2024, 1, 15, 10, 30, 0);

    final model = LocationDataModel(
      id: 1,
      latitude: 12.345678,
      longitude: 98.765432,
      altitude: 50.0,
      speed: 1.5,
      heading: 90.0,
      accuracy: 5.0,
      timestamp: t,
    );

    test('toJson round-trips through fromJson', () {
      final restored = LocationDataModel.fromJson(model.toJson());
      expect(restored.latitude, model.latitude);
      expect(restored.longitude, model.longitude);
      expect(restored.altitude, model.altitude);
      expect(restored.speed, model.speed);
      expect(restored.heading, model.heading);
      expect(restored.accuracy, model.accuracy);
      expect(restored.timestamp.toIso8601String(), t.toIso8601String());
    });

    test('fromJson defaults optional fields to 0.0', () {
      final m = LocationDataModel.fromJson({
        'latitude': 1.0,
        'longitude': 2.0,
        'timestamp': t.toIso8601String(),
      });
      expect(m.altitude, 0.0);
      expect(m.speed, 0.0);
      expect(m.heading, 0.0);
      expect(m.accuracy, 0.0);
    });

    // Feature 5: toMap must store all fields so SQLite captures full data
    test('toMap includes altitude/speed/heading/accuracy (Feature 5)', () {
      final map = model.toMap();
      expect(map.keys.toSet(), {
        'latitude', 'longitude', 'altitude', 'speed', 'heading', 'accuracy', 'timestamp'
      });
      expect(map['altitude'], 50.0);
      expect(map['speed'], 1.5);
      expect(map['heading'], 90.0);
      expect(map['accuracy'], 5.0);
    });
  });

  // ─── WaypointUtils ─────────────────────────────────────────────────────────

  group('WaypointUtils', () {
    test('processLocationData maps all fields', () {
      final t = DateTime(2024, 6, 1, 8, 0, 0);
      final result = WaypointUtils.processLocationData({
        'latitude': 13.0,
        'longitude': 77.5,
        'altitude': 100.0,
        'speed': 2.0,
        'heading': 180.0,
        'accuracy': 3.0,
        'timestamp': t.toIso8601String(),
      });
      expect(result.latitude, 13.0);
      expect(result.altitude, 100.0);
      expect(result.heading, 180.0);
    });

    test('processLocationData defaults missing optional fields to 0.0', () {
      final t = DateTime(2024, 6, 1);
      final result = WaypointUtils.processLocationData(
          {'latitude': 1.0, 'longitude': 2.0, 'timestamp': t.toIso8601String()});
      expect(result.altitude, 0.0);
      expect(result.speed, 0.0);
    });
  });

  // ─── Geofence model ────────────────────────────────────────────────────────

  group('Geofence model', () {
    const g = Geofence(
        id: 'office', latitude: 12.345, longitude: 98.765, radiusMeters: 100);

    test('toJson / fromJson round-trip', () {
      final restored = Geofence.fromJson(g.toJson());
      expect(restored.id, g.id);
      expect(restored.latitude, g.latitude);
      expect(restored.radiusMeters, g.radiusMeters);
    });

    test('fromJson coerces int coordinates to double', () {
      final g2 = Geofence.fromJson(
          {'id': 'test', 'latitude': 12, 'longitude': 98, 'radiusMeters': 50});
      expect(g2.latitude, 12.0);
      expect(g2.radiusMeters, 50.0);
    });

    test('toString contains id and radius', () {
      expect(g.toString(), contains('office'));
      expect(g.toString(), contains('100.0m'));
    });

    // Feature 7: list serialisation used for SharedPreferences persistence
    test('list serialisation round-trips (Feature 7)', () {
      final list = [
        const Geofence(id: 'a', latitude: 1.0, longitude: 2.0, radiusMeters: 50),
        const Geofence(id: 'b', latitude: 3.0, longitude: 4.0, radiusMeters: 200),
      ];
      final encoded = jsonEncode(list.map((x) => x.toJson()).toList());
      final decoded = (jsonDecode(encoded) as List)
          .map((e) => Geofence.fromJson(e as Map<String, dynamic>))
          .toList();
      expect(decoded.length, 2);
      expect(decoded[0].id, 'a');
      expect(decoded[1].radiusMeters, 200.0);
    });
  });

  // ─── Feature 7: Geofence distance detection ────────────────────────────────

  group('Feature 7 — Geofence distance detection', () {
    const fenceLat = 12.9716;
    const fenceLng = 77.5946;
    const radius = 100.0;

    test('same point is inside geofence', () {
      final d = Geolocator.distanceBetween(fenceLat, fenceLng, fenceLat, fenceLng);
      expect(d, lessThan(radius));
    });

    test('point ~50 m away is inside 100 m geofence', () {
      // 0.00045° latitude ≈ 50 m
      const nearLat = 12.9716 + 0.00045;
      final d = Geolocator.distanceBetween(nearLat, fenceLng, fenceLat, fenceLng);
      expect(d, lessThan(radius));
    });

    test('point ~500 m away is outside 100 m geofence', () {
      // 0.0045° latitude ≈ 500 m
      const farLat = 12.9716 + 0.0045;
      final d = Geolocator.distanceBetween(farLat, fenceLng, fenceLat, fenceLng);
      expect(d, greaterThan(radius));
    });

    test('enter/exit state transition logic fires events on transitions only', () {
      final geofenceStates = <String, bool>{};
      const geofenceId = 'zone1';
      const geofenceRadius = 100.0;

      bool checkTransition(double distance) {
        final wasInside = geofenceStates[geofenceId] ?? false;
        final isInside = distance <= geofenceRadius;
        if (isInside != wasInside) {
          geofenceStates[geofenceId] = isInside;
          return true; // event fired
        }
        return false;
      }

      expect(checkTransition(150.0), false); // outside, no prior state — no event
      expect(checkTransition(50.0), true);   // enter
      expect(checkTransition(60.0), false);  // still inside — no duplicate event
      expect(checkTransition(200.0), true);  // exit
      expect(checkTransition(300.0), false); // still outside — no duplicate event
      expect(geofenceStates[geofenceId], false);
    });
  });

  // ─── Feature 4: Time-interval filter ──────────────────────────────────────

  group('Feature 4 — Time-interval filter', () {
    test('skips fix when elapsed time is below interval', () {
      DateTime? lastUpdate;
      const interval = 30;

      bool shouldProcess(DateTime now) {
        if (interval > 0 && lastUpdate != null &&
            now.difference(lastUpdate!).inSeconds < interval) {
          return false;
        }
        lastUpdate = now;
        return true;
      }

      final t0 = DateTime(2024, 1, 1, 0, 0, 0);
      expect(shouldProcess(t0), true);
      expect(shouldProcess(t0.add(const Duration(seconds: 10))), false);
      expect(shouldProcess(t0.add(const Duration(seconds: 29))), false);
      expect(shouldProcess(t0.add(const Duration(seconds: 30))), true);
      expect(shouldProcess(t0.add(const Duration(seconds: 60))), true);
    });

    test('processes every fix when timeInterval is 0', () {
      DateTime? lastUpdate;
      const interval = 0;

      bool shouldProcess(DateTime now) {
        if (interval > 0 && lastUpdate != null &&
            now.difference(lastUpdate!).inSeconds < interval) {
          return false;
        }
        lastUpdate = now;
        return true;
      }

      final t0 = DateTime(2024, 1, 1);
      expect(shouldProcess(t0), true);
      expect(shouldProcess(t0.add(const Duration(seconds: 1))), true);
      expect(shouldProcess(t0.add(const Duration(seconds: 2))), true);
    });
  });

  // ─── Feature 6: Custom HTTP headers ───────────────────────────────────────

  group('Feature 6 — Custom HTTP headers', () {
    // Mirror of _buildHeaders from location_service.dart
    Map<String, String> buildHeaders(
        String? accessToken, Map<String, String>? customHeaders) {
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (customHeaders != null) headers.addAll(customHeaders);
      if (accessToken != null) headers['Authorization'] = 'Bearer $accessToken';
      return headers;
    }

    test('always includes Content-Type', () {
      expect(buildHeaders(null, null)['Content-Type'], 'application/json');
    });

    test('adds Bearer authorization when accessToken provided', () {
      expect(buildHeaders('my-token', null)['Authorization'], 'Bearer my-token');
    });

    test('customHeaders are merged into request', () {
      final h = buildHeaders(null, {'X-API-Key': 'key123', 'X-Device': 'dev1'});
      expect(h['X-API-Key'], 'key123');
      expect(h['X-Device'], 'dev1');
    });

    test('customHeaders and accessToken can coexist', () {
      final h = buildHeaders('tok', {'X-App': 'betracky'});
      expect(h['Authorization'], 'Bearer tok');
      expect(h['X-App'], 'betracky');
      expect(h['Content-Type'], 'application/json');
    });

    test('no Authorization header when accessToken is null', () {
      final h = buildHeaders(null, {'X-App': 'test'});
      expect(h.containsKey('Authorization'), false);
    });
  });

  // ─── Feature 5: Upload payload construction ────────────────────────────────

  group('Feature 5 — Upload payload', () {
    final loc = LocationDataModel(
      latitude: 12.345678,
      longitude: 98.765432,
      altitude: 50.2,
      speed: 1.5,
      heading: 90.0,
      accuracy: 5.0,
      timestamp: DateTime(2024, 1, 15, 10, 30, 0),
    );

    // Mirror of _buildPayload from location_service.dart
    List<Map<String, dynamic>> buildPayload(
        List<LocationDataModel> locs, int id, bool uploadFullData) {
      return locs.map((l) {
        final entry = <String, dynamic>{
          'l_id': id,
          'latitude': l.latitude,
          'longitude': l.longitude,
          'actual_created_time': l.timestamp.toIso8601String(),
        };
        if (uploadFullData) {
          entry['altitude'] = l.altitude;
          entry['speed'] = l.speed;
          entry['heading'] = l.heading;
          entry['accuracy'] = l.accuracy;
        }
        return entry;
      }).toList();
    }

    test('basic payload has only required fields', () {
      final payload = buildPayload([loc], 42, false);
      expect(payload.length, 1);
      expect(payload[0].keys.toSet(),
          {'l_id', 'latitude', 'longitude', 'actual_created_time'});
      expect(payload[0]['l_id'], 42);
      expect(payload[0]['latitude'], 12.345678);
    });

    test('uploadFullData adds altitude, speed, heading, accuracy', () {
      final payload = buildPayload([loc], 42, true);
      expect(payload[0]['altitude'], 50.2);
      expect(payload[0]['speed'], 1.5);
      expect(payload[0]['heading'], 90.0);
      expect(payload[0]['accuracy'], 5.0);
    });

    test('batch payload has one entry per location', () {
      final locs = List.generate(
          3,
          (i) => LocationDataModel(
                latitude: i.toDouble(),
                longitude: i.toDouble(),
                timestamp: DateTime(2024, 1, i + 1),
              ));
      final payload = buildPayload(locs, 1, false);
      expect(payload.length, 3);
      expect(payload[2]['latitude'], 2.0);
    });
  });

  // ─── Feature 1 & 8: DatabaseHelper ────────────────────────────────────────

  group('Feature 1 & 8 — DatabaseHelper', () {
    late DatabaseHelper db;

    final sampleLoc = LocationDataModel(
      latitude: 12.0,
      longitude: 98.0,
      altitude: 30.0,
      speed: 0.5,
      heading: 45.0,
      accuracy: 4.0,
      timestamp: DateTime(2024, 6, 1, 10, 0, 0),
    );

    setUp(() async {
      await DatabaseHelper.resetForTesting();
      db = DatabaseHelper();
    });

    // Feature 8 — Location storage and query API
    test('insertLocation increments countLocations (Feature 8)', () async {
      expect(await db.countLocations(), 0);
      await db.insertLocation(sampleLoc);
      expect(await db.countLocations(), 1);
      await db.insertLocation(sampleLoc);
      expect(await db.countLocations(), 2);
    });

    test('getBatchLocation respects limit (Feature 8)', () async {
      for (var i = 0; i < 60; i++) {
        await db.insertLocation(LocationDataModel(
          latitude: i.toDouble(),
          longitude: i.toDouble(),
          timestamp: DateTime(2024, 1, 1).add(Duration(minutes: i)),
        ));
      }
      final batch = await db.getBatchLocation(50);
      expect(batch.length, 50);
    });

    test('getBatchLocation returns all full fields (Feature 5)', () async {
      await db.insertLocation(sampleLoc);
      final results = await db.getBatchLocation(1);
      expect(results.first.altitude, 30.0);
      expect(results.first.speed, 0.5);
      expect(results.first.heading, 45.0);
      expect(results.first.accuracy, 4.0);
    });

    test('deleteBatchLocations removes correct rows (Feature 8)', () async {
      await db.insertLocation(sampleLoc);
      await db.insertLocation(sampleLoc);
      final batch = await db.getBatchLocation(50);
      final ids = batch.map((l) => l.id).whereType<int>().toList();
      await db.deleteBatchLocations(ids);
      expect(await db.countLocations(), 0);
    });

    test('getLocationsByDateRange filters by date range (Feature 8)', () async {
      final base = DateTime(2024, 1, 1);
      for (var i = 0; i < 5; i++) {
        await db.insertLocation(LocationDataModel(
          latitude: i.toDouble(),
          longitude: i.toDouble(),
          timestamp: base.add(Duration(days: i)),
        ));
      }
      // Jan 1 = index 0, Jan 2 = index 1, … Jan 5 = index 4
      final results = await db.getLocationsByDateRange(
        from: DateTime(2024, 1, 2),
        to: DateTime(2024, 1, 4),
      );
      expect(results.length, 3); // Jan 2, 3, 4
    });

    test('getLocationsByDateRange with no filters returns all (Feature 8)', () async {
      await db.insertLocation(sampleLoc);
      await db.insertLocation(sampleLoc);
      expect((await db.getLocationsByDateRange()).length, 2);
    });

    test('clearLocations wipes all rows (Feature 8)', () async {
      await db.insertLocation(sampleLoc);
      await db.insertLocation(sampleLoc);
      await db.clearLocations();
      expect(await db.countLocations(), 0);
    });

    // Feature 1 — Retry queue
    test('insertPendingUpload increments countPendingUploads (Feature 1)', () async {
      expect(await db.countPendingUploads(), 0);
      await db.insertPendingUpload(
          payload: '[{"l_id":1}]', url: 'https://example.com', accessToken: 'tok');
      expect(await db.countPendingUploads(), 1);
    });

    test('getPendingUploads only returns records due for retry (Feature 1)', () async {
      await db.insertPendingUpload(payload: '[]', url: 'https://example.com');
      await db.insertPendingUpload(payload: '[]', url: 'https://example.com');

      // next_retry_at = now + 1 min → not yet due
      final notDue = await db.getPendingUploads(DateTime.now(), 5);
      expect(notDue.length, 0);

      // 1 hour in future → both are due
      final due = await db.getPendingUploads(
          DateTime.now().add(const Duration(hours: 1)), 5);
      expect(due.length, 2);
    });

    test('deletePendingUpload removes a specific record (Feature 1)', () async {
      await db.insertPendingUpload(payload: '[]', url: 'https://example.com');
      final records = await db.getPendingUploads(
          DateTime.now().add(const Duration(hours: 1)), 5);
      await db.deletePendingUpload(records.first['id'] as int);
      expect(await db.countPendingUploads(), 0);
    });

    test('incrementRetryAttempt applies exponential backoff (Feature 1)', () async {
      await db.insertPendingUpload(payload: '[]', url: 'https://example.com');
      final records = await db.getPendingUploads(
          DateTime.now().add(const Duration(hours: 1)), 5);
      final id = records.first['id'] as int;

      // Increment: attempt 0 → 1 (delay = 2^1 = 2 min)
      await db.incrementRetryAttempt(id, 0, 5);

      // Should appear in 3-min future query
      final updated = await db.getPendingUploads(
          DateTime.now().add(const Duration(minutes: 3)), 5);
      expect(updated.length, 1);
      expect(updated.first['attempts'], 1);
    });

    test('incrementRetryAttempt deletes record at maxRetries (Feature 1)', () async {
      await db.insertPendingUpload(payload: '[]', url: 'https://example.com');
      final records = await db.getPendingUploads(
          DateTime.now().add(const Duration(hours: 1)), 5);
      final id = records.first['id'] as int;

      // Simulating attempt 4 → 5 = maxRetries (5)
      await db.incrementRetryAttempt(id, 4, 5);
      expect(await db.countPendingUploads(), 0);
    });

    test('customHeaders stored as JSON and recoverable (Feature 6)', () async {
      await db.insertPendingUpload(
        payload: '[]',
        url: 'https://example.com',
        customHeaders: {'X-API-Key': 'abc', 'X-App': 'test'},
      );
      final records = await db.getPendingUploads(
          DateTime.now().add(const Duration(hours: 1)), 5);
      final headersJson = records.first['custom_headers'] as String;
      final decoded = Map<String, String>.from(jsonDecode(headersJson));
      expect(decoded['X-API-Key'], 'abc');
      expect(decoded['X-App'], 'test');
    });
  });
}
