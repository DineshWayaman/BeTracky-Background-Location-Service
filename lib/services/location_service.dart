import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:betracky_background_location/models/geofence.dart';
import 'package:betracky_background_location/models/location.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:workmanager/workmanager.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:betracky_background_location/utils/database_helper.dart';

// Sentinel used when no id is provided — replaced with epoch ms at upload time.
const int _kDefaultIdSentinel = 1112333322111;
const String _kRetryTaskName = 'betracky_retry_uploads';

// ─── Top-level helpers (accessible from Workmanager isolate) ────────────────

Map<String, String> _buildHeaders(
  String? accessToken,
  Map<String, String>? customHeaders,
) {
  final headers = <String, String>{'Content-Type': 'application/json'};
  if (customHeaders != null) headers.addAll(customHeaders);
  if (accessToken != null) headers['Authorization'] = 'Bearer $accessToken';
  return headers;
}

List<Map<String, dynamic>> _buildPayload(
  List<LocationDataModel> locations,
  int id,
  bool uploadFullData,
) {
  return locations.map((loc) {
    final entry = <String, dynamic>{
      'l_id': id,
      'latitude': loc.latitude,
      'longitude': loc.longitude,
      'actual_created_time': loc.timestamp.toIso8601String(),
    };
    if (uploadFullData) {
      entry['altitude'] = loc.altitude;
      entry['speed'] = loc.speed;
      entry['heading'] = loc.heading;
      entry['accuracy'] = loc.accuracy;
    }
    return entry;
  }).toList();
}

/// Attempts a single HTTP POST. Returns true on HTTP 200.
Future<bool> _attemptUpload(
  String payloadJson,
  String url,
  String? accessToken,
  Map<String, String>? customHeaders,
) async {
  final client = http.Client();
  try {
    final response = await client
        .post(
          Uri.parse(url),
          headers: _buildHeaders(accessToken, customHeaders),
          body: payloadJson,
        )
        .timeout(const Duration(seconds: 30));
    return response.statusCode == 200;
  } on TimeoutException {
    debugPrint('BeTracky upload timed out');
    return false;
  } catch (e) {
    debugPrint('BeTracky upload error: $e');
    return false;
  } finally {
    client.close();
  }
}

/// Loads geofences from SharedPreferences. Safe to call from any isolate.
List<Geofence> _loadGeofencesFromPrefs(SharedPreferences prefs) {
  final json = prefs.getString('geofences');
  if (json == null) return [];
  try {
    final list = jsonDecode(json) as List;
    return list
        .map((e) => Geofence.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return [];
  }
}

/// Retries pending uploads from the SQLite queue. Called from Workmanager.
Future<void> _retryPendingUploads() async {
  final prefs = await SharedPreferences.getInstance();
  final url = prefs.getString('url');
  if (url == null) return;

  final maxRetries = prefs.getInt('maxRetries') ?? 5;
  final accessToken = prefs.getString('access_token');
  Map<String, String>? customHeaders;
  final headersJson = prefs.getString('customHeaders');
  if (headersJson != null) {
    try {
      customHeaders = Map<String, String>.from(jsonDecode(headersJson));
    } catch (_) {}
  }

  final dbHelper = DatabaseHelper();
  final pending = await dbHelper.getPendingUploads(DateTime.now(), maxRetries);

  for (final upload in pending) {
    final uploadUrl = (upload['url'] as String?) ?? url;
    final uploadAccessToken = (upload['access_token'] as String?) ?? accessToken;

    Map<String, String>? uploadHeaders;
    final uploadHeadersJson = upload['custom_headers'] as String?;
    if (uploadHeadersJson != null) {
      try {
        uploadHeaders = Map<String, String>.from(jsonDecode(uploadHeadersJson));
      } catch (_) {}
    }

    final success = await _attemptUpload(
      upload['payload'] as String,
      uploadUrl,
      uploadAccessToken,
      uploadHeaders ?? customHeaders,
    );

    final id = upload['id'] as int;
    final attempts = upload['attempts'] as int;
    if (success) {
      await dbHelper.deletePendingUpload(id);
    } else {
      await dbHelper.incrementRetryAttempt(id, attempts, maxRetries);
    }
  }
}

// ─── Main Class ─────────────────────────────────────────────────────────────

@pragma('vm:entry-point')
class BeTrackyBackgroundLocation {
  static final _service = FlutterBackgroundService();
  static StreamSubscription<Position>? _positionStreamSubscription;

  // ── Service Lifecycle ────────────────────────────────────────────────────

  /// Starts background location tracking.
  ///
  /// - [distanceFilter]: Minimum metres between location updates.
  /// - [accuracy]: Desired GPS accuracy.
  /// - [startOnBoot]: Restart the service automatically on device reboot.
  /// - [foregroundService]: Show a persistent foreground notification (Android).
  /// - [url]: HTTP endpoint to POST locations to. Optional.
  /// - [accessToken]: Bearer token for your endpoint. Optional.
  /// - [offlineEnabled]: Buffer locations in SQLite and upload in batches of 50.
  /// - [id]: Value sent as `l_id` in each upload payload. Defaults to epoch ms.
  /// - [timeInterval]: Minimum seconds between location saves (0 = unlimited).
  /// - [uploadFullData]: Include altitude, speed, heading, accuracy in payload.
  /// - [customHeaders]: Additional HTTP headers merged into every upload request.
  /// - [maxRetries]: Maximum retry attempts for failed uploads. Default: 5.
  static Future<void> startService({
    required int distanceFilter,
    required LocationAccuracy accuracy,
    required bool startOnBoot,
    required bool foregroundService,
    String? url,
    String? accessToken,
    bool? offlineEnabled,
    int? id,
    int? timeInterval,
    bool? uploadFullData,
    Map<String, String>? customHeaders,
    int? maxRetries,
  }) async {
    if (url != null && Uri.tryParse(url) == null) {
      throw ArgumentError('Invalid URL: $url');
    }

    // Guard: location permission must be granted before the service can track.
    if (Platform.isAndroid || Platform.isIOS) {
      final locationStatus = await Geolocator.checkPermission();
      if (locationStatus == LocationPermission.denied ||
          locationStatus == LocationPermission.deniedForever) {
        throw StateError(
          'BeTracky: location permission not granted. '
          'Call Geolocator.requestPermission() before startService().',
        );
      }
    }

    // Reminder for Android 13+: POST_NOTIFICATIONS must also be granted at
    // runtime so the foreground service notification is visible. Without it
    // the service starts silently and may be killed when the app is closed.
    // Add to your app: await Permission.notification.request();  (permission_handler)
    if (foregroundService && Platform.isAndroid) {
      debugPrint(
        'BeTracky: verify android.permission.POST_NOTIFICATIONS is granted '
        'on Android 13+ or the foreground notification will be suppressed.',
      );
    }

    await _service.configure(
      iosConfiguration: IosConfiguration(
        onBackground: onBackground,
        autoStart: startOnBoot,
      ),
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        isForegroundMode: foregroundService,
        autoStart: startOnBoot,
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('offlineEnabled', offlineEnabled ?? false);
    await prefs.setInt('id', id ?? _kDefaultIdSentinel);
    await prefs.setInt('distanceFilter', distanceFilter);
    await prefs.setString('accuracy', accuracy.name);
    await prefs.setInt('timeInterval', timeInterval ?? 0);
    await prefs.setBool('uploadFullData', uploadFullData ?? false);
    await prefs.setInt('maxRetries', maxRetries ?? 5);
    await prefs.setBool('isPaused', false);
    if (url != null) await prefs.setString('url', url);
    if (accessToken != null) await prefs.setString('access_token', accessToken);
    if (customHeaders != null) {
      await prefs.setString('customHeaders', jsonEncode(customHeaders));
    }

    await _service.startService();

    _service.invoke('setParams', {
      'url': url,
      'access_token': accessToken,
      'offlineEnabled': offlineEnabled,
      'customHeaders': customHeaders != null ? jsonEncode(customHeaders) : null,
    });

    Workmanager().initialize(callbackDispatcher);
    if (url != null) {
      Workmanager().registerPeriodicTask(
        _kRetryTaskName,
        'retryUploads',
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    }
  }

  @pragma('vm:entry-point')
  static Future<void> stopService() async {
    _positionStreamSubscription?.cancel();
    _service.invoke('stopService');
    await Workmanager().cancelByUniqueName(_kRetryTaskName);
  }

  // ── Tracking Control ─────────────────────────────────────────────────────

  /// Pauses location updates without stopping the service or losing config.
  static Future<void> pauseTracking() async {
    _service.invoke('pauseTracking');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isPaused', true);
  }

  /// Resumes location updates after [pauseTracking].
  static Future<void> resumeTracking() async {
    _service.invoke('resumeTracking');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isPaused', false);
  }

  /// Returns true if the service is running and not paused.
  static Future<bool> isTracking() async {
    if (!await _service.isRunning()) return false;
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool('isPaused') ?? false);
  }

  // ── Status ───────────────────────────────────────────────────────────────

  /// Returns current service status snapshot.
  ///
  /// Keys: `isRunning` (bool), `isTracking` (bool), `pendingUploads` (int).
  static Future<Map<String, dynamic>> getStatus() async {
    final isRunning = await _service.isRunning();
    final prefs = await SharedPreferences.getInstance();
    final isPaused = prefs.getBool('isPaused') ?? false;
    var pendingCount = 0;
    try {
      pendingCount = await DatabaseHelper().countPendingUploads();
    } catch (_) {}
    return {
      'isRunning': isRunning,
      'isTracking': isRunning && !isPaused,
      'pendingUploads': pendingCount,
    };
  }

  // ── Geofencing ───────────────────────────────────────────────────────────

  /// Adds or replaces a circular geofence. Fires `geofenceEvent` stream events
  /// with `{ id, event: 'enter'|'exit', latitude, longitude, distance }`.
  static Future<void> addGeofence(Geofence geofence) async {
    final prefs = await SharedPreferences.getInstance();
    final list = _loadGeofencesFromPrefs(prefs);
    list.removeWhere((g) => g.id == geofence.id);
    list.add(geofence);
    await prefs.setString(
      'geofences',
      jsonEncode(list.map((g) => g.toJson()).toList()),
    );
    _service.invoke('updateGeofences', null);
  }

  /// Removes a geofence by ID.
  static Future<void> removeGeofence(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = _loadGeofencesFromPrefs(prefs);
    list.removeWhere((g) => g.id == id);
    await prefs.setString(
      'geofences',
      jsonEncode(list.map((g) => g.toJson()).toList()),
    );
    _service.invoke('updateGeofences', null);
  }

  /// Removes all registered geofences.
  static Future<void> clearGeofences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('geofences');
    _service.invoke('updateGeofences', null);
  }

  // ── Stored Location Query ─────────────────────────────────────────────────

  /// Returns locally stored locations filtered by optional date range.
  static Future<List<LocationDataModel>> getStoredLocations({
    DateTime? from,
    DateTime? to,
    int limit = 500,
  }) {
    return DatabaseHelper()
        .getLocationsByDateRange(from: from, to: to, limit: limit);
  }

  /// Returns the number of locations currently stored locally.
  static Future<int> getStoredLocationCount() {
    return DatabaseHelper().countLocations();
  }

  /// Deletes all locally stored locations.
  static Future<void> clearStoredLocations() {
    return DatabaseHelper().clearLocations();
  }

  // ── Background Service Entry Points ──────────────────────────────────────

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();

    if (service is AndroidServiceInstance) {
      try {
        await service.setForegroundNotificationInfo(
          title: 'Location Tracking',
          content: 'Tracking your location in the background',
        );
      } catch (e) {
        debugPrint('BeTracky foreground notification error: $e');
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final dbHelper = DatabaseHelper();

    // Load all config into closure-captured locals so stream listener + event
    // listeners can read the latest values without restarting the stream.
    String? url = prefs.getString('url');
    String? accessToken = prefs.getString('access_token');
    bool offlineEnabled = prefs.getBool('offlineEnabled') ?? false;
    int id = prefs.getInt('id') ?? _kDefaultIdSentinel;
    final int distanceFilter = prefs.getInt('distanceFilter') ?? 0;
    final String accuracyName = prefs.getString('accuracy') ?? 'high';
    final LocationAccuracy accuracy =
        LocationAccuracy.values.byName(accuracyName);
    final int timeInterval = prefs.getInt('timeInterval') ?? 0;
    final bool uploadFullData = prefs.getBool('uploadFullData') ?? false;

    Map<String, String>? customHeaders;
    final headersJson = prefs.getString('customHeaders');
    if (headersJson != null) {
      try {
        customHeaders = Map<String, String>.from(jsonDecode(headersJson));
      } catch (_) {}
    }

    List<Geofence> geofences = _loadGeofencesFromPrefs(prefs);
    final Map<String, bool> geofenceStates = {};
    DateTime? lastUpdate;

    // ── Stream creation helper ──────────────────────────────────────────────
    void startStream() {
      _positionStreamSubscription?.cancel();
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: accuracy,
          distanceFilter: distanceFilter,
        ),
      ).listen(
        (Position position) async {
          try {
            // F4: Time-interval filter
            final now = DateTime.now();
            if (timeInterval > 0 && lastUpdate != null) {
              if (now.difference(lastUpdate!).inSeconds < timeInterval) return;
            }
            lastUpdate = now;

            final locationData = LocationDataModel(
              latitude: position.latitude,
              longitude: position.longitude,
              altitude: position.altitude,
              speed: position.speed,
              heading: position.heading,
              accuracy: position.accuracy,
              timestamp: now,
            );

            service.invoke('update', locationData.toJson());

            // F7: Geofence evaluation
            for (final geofence in geofences) {
              final distance = Geolocator.distanceBetween(
                position.latitude,
                position.longitude,
                geofence.latitude,
                geofence.longitude,
              );
              final wasInside = geofenceStates[geofence.id] ?? false;
              final isInside = distance <= geofence.radiusMeters;
              if (isInside != wasInside) {
                geofenceStates[geofence.id] = isInside;
                service.invoke('geofenceEvent', {
                  'id': geofence.id,
                  'event': isInside ? 'enter' : 'exit',
                  'latitude': position.latitude,
                  'longitude': position.longitude,
                  'distance': distance,
                });
              }
            }

            // Always store locally when offlineEnabled, regardless of whether
            // a server URL is configured (supports local-only storage use case).
            if (offlineEnabled) {
              try {
                await dbHelper.insertLocation(locationData);
                final storedCount = await dbHelper.countLocations();
                service.invoke('locationCount', {'stored': storedCount});
              } catch (e) {
                debugPrint('BeTracky local DB insert error: $e');
              }
            }

            final activeUrl = url;
            if (activeUrl == null) return;

            final activeId = id == _kDefaultIdSentinel
                ? DateTime.now().millisecondsSinceEpoch
                : id;

            if (offlineEnabled) {
              final locations = await dbHelper.getBatchLocation(50);
              if (locations.length >= 50) {
                final payloadJson = jsonEncode(
                  _buildPayload(locations, activeId, uploadFullData),
                );
                final success = await _attemptUpload(
                  payloadJson,
                  activeUrl,
                  accessToken,
                  customHeaders,
                );
                if (success) {
                  final ids =
                      locations.map((l) => l.id).whereType<int>().toList();
                  await dbHelper.deleteBatchLocations(ids);
                } else {
                  await dbHelper.insertPendingUpload(
                    payload: payloadJson,
                    url: activeUrl,
                    accessToken: accessToken,
                    customHeaders: customHeaders,
                  );
                }
                service.invoke('uploadStatus', {
                  'success': success,
                  'uploaded': success ? locations.length : 0,
                  'pending': await dbHelper.countPendingUploads(),
                  if (!success) 'error': 'Upload failed — queued for retry',
                });
              }
            } else {
              final payloadJson = jsonEncode(
                _buildPayload([locationData], activeId, uploadFullData),
              );
              final success = await _attemptUpload(
                payloadJson,
                activeUrl,
                accessToken,
                customHeaders,
              );
              if (!success) {
                await dbHelper.insertPendingUpload(
                  payload: payloadJson,
                  url: activeUrl,
                  accessToken: accessToken,
                  customHeaders: customHeaders,
                );
              }
              service.invoke('uploadStatus', {
                'success': success,
                'uploaded': success ? 1 : 0,
                'pending': await dbHelper.countPendingUploads(),
                if (!success) 'error': 'Upload failed — queued for retry',
              });
            }
          } catch (e) {
            debugPrint('BeTracky stream error: $e');
          }
        },
        onError: (e) => debugPrint('BeTracky geolocator error: $e'),
      );
    }

    // ── Service event listeners ─────────────────────────────────────────────

    service.on('setParams').listen((data) {
      if (data == null) return;
      final newUrl = data['url'] as String?;
      final newAccessToken = data['access_token'] as String?;
      final newOfflineEnabled = data['offlineEnabled'] as bool?;
      final newHeadersJson = data['customHeaders'] as String?;

      if (newUrl != null && newUrl != url) {
        prefs.setString('url', newUrl);
        url = newUrl;
      }
      if (newAccessToken != null && newAccessToken != accessToken) {
        prefs.setString('access_token', newAccessToken);
        accessToken = newAccessToken;
      }
      if (newOfflineEnabled != null && newOfflineEnabled != offlineEnabled) {
        prefs.setBool('offlineEnabled', newOfflineEnabled);
        offlineEnabled = newOfflineEnabled;
      }
      if (newHeadersJson != null) {
        try {
          customHeaders = Map<String, String>.from(jsonDecode(newHeadersJson));
        } catch (_) {}
      }
    });

    service.on('stopService').listen((_) {
      _positionStreamSubscription?.cancel();
      service.stopSelf();
    });

    // F3: Pause / Resume
    service.on('pauseTracking').listen((_) {
      _positionStreamSubscription?.cancel();
      _positionStreamSubscription = null;
      service.invoke('serviceStatus', {
        'running': true,
        'tracking': false,
        'offlineEnabled': offlineEnabled,
      });
    });

    service.on('resumeTracking').listen((_) {
      startStream();
      service.invoke('serviceStatus', {
        'running': true,
        'tracking': true,
        'offlineEnabled': offlineEnabled,
      });
    });

    // F7: Runtime geofence updates
    service.on('updateGeofences').listen((_) {
      geofences = _loadGeofencesFromPrefs(prefs);
      geofenceStates.removeWhere(
        (gId, _) => !geofences.any((g) => g.id == gId),
      );
    });

    // F2: Emit initial service status
    service.invoke('serviceStatus', {
      'running': true,
      'tracking': !(prefs.getBool('isPaused') ?? false),
      'offlineEnabled': offlineEnabled,
    });

    if (!(prefs.getBool('isPaused') ?? false)) {
      startStream();
    }
  }

  static Future<bool> onBackground(ServiceInstance service) async {
    return true;
  }
}

// ─── Workmanager Entry Point ─────────────────────────────────────────────────

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == 'retryUploads') {
      await _retryPendingUploads();
    } else {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
      );
      debugPrint(
        'BeTracky background fix: ${position.latitude}, ${position.longitude}',
      );
    }
    return true;
  });
}
