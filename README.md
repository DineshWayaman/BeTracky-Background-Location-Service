# BeTracky Background Location Service

A Flutter package for background location tracking with geofencing, offline storage, upload retry, and full server upload support.

## Features

- Background location tracking (works when the app is closed)
- Configurable distance filter, accuracy, and time-interval filter
- Start on boot and foreground service support
- Pause / Resume tracking without losing configuration
- Offline mode: buffer locations in SQLite and upload in batches of 50
- Upload retry queue with exponential backoff (1 min → 2 min → … → 60 min cap)
- Upload full location fields: altitude, speed, heading, accuracy
- Custom HTTP headers for any backend auth scheme
- Circular geofencing with enter/exit stream events (pure Dart, no extra dependencies)
- Stored location query API for analytics and route replay
- Upload status, service state, and location count stream events

## Installation

```yaml
dependencies:
  betracky_background_location: ^2.1.0
```

## Android setup

### AndroidManifest.xml

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>  <!-- Required Android 13+ -->
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>

<!-- Inside <application> -->
<service
  android:name="com.transistorsoft.flutter.backgroundfetch.HeadlessTask"
  android:permission="android.permission.BIND_JOB_SERVICE"
  android:exported="true"/>
```

### Runtime permissions (critical)

You **must** request both location and notification permissions at runtime before calling `startService`. If `POST_NOTIFICATIONS` is not granted on Android 13+, the foreground notification is silently suppressed and the OS will kill the service when the app is closed.

```dart
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

Future<void> requestPermissions() async {
  // Location (required for tracking)
  await Geolocator.requestPermission();
  await Permission.locationAlways.request();  // for background tracking

  // Notification (required for foreground service on Android 13+)
  await Permission.notification.request();
}

// Call BEFORE startService:
await requestPermissions();
await BeTrackyBackgroundLocation.startService(...);
```

> **Note:** `startService` will throw a `StateError` if location permission is denied. The service starts without error if `POST_NOTIFICATIONS` is denied, but the persistent notification will not appear and the service may be killed by the OS on Android 13+ when the app is closed.

## iOS setup

Add to `Info.plist`:

```xml
<key>NSLocationAlwaysUsageDescription</key>
<string>Location is required to track your location</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Location is required to track your location</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Location is required to track your location</string>
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>location</string>
</array>
```

## Usage

### Start tracking

```dart
import 'package:betracky_background_location/betracky_background_location.dart';

await BeTrackyBackgroundLocation.startService(
  distanceFilter: 10,             // minimum metres between updates
  accuracy: LocationAccuracy.high,
  startOnBoot: true,
  foregroundService: true,
  url: 'https://your-server.com/locations', // optional
  accessToken: 'your-bearer-token',          // optional
  id: 42,                                    // optional — sent as l_id
  offlineEnabled: true,                      // buffer locally and batch upload
  timeInterval: 30,                          // at most one update per 30 seconds
  uploadFullData: true,                      // include altitude, speed, heading
  customHeaders: {'X-API-Key': 'abc123'},    // any extra headers
  maxRetries: 5,                             // retry failed uploads up to 5 times
);
```

### Stop tracking

```dart
await BeTrackyBackgroundLocation.stopService();
```

### Pause / Resume (without stopping the service)

```dart
await BeTrackyBackgroundLocation.pauseTracking();
await BeTrackyBackgroundLocation.resumeTracking();
final bool active = await BeTrackyBackgroundLocation.isTracking();
```

### Service status

```dart
final status = await BeTrackyBackgroundLocation.getStatus();
// { 'isRunning': true, 'isTracking': true, 'pendingUploads': 3 }
```

### Stream events

```dart
import 'package:flutter_background_service/flutter_background_service.dart';

final svc = FlutterBackgroundService();

// Live location updates
svc.on('update').listen((data) {
  final loc = LocationDataModel.fromJson(data!);
});

// Upload success / failure
svc.on('uploadStatus').listen((data) {
  // { 'success': true, 'uploaded': 50, 'pending': 0 }
});

// Service state changes
svc.on('serviceStatus').listen((data) {
  // { 'running': true, 'tracking': true, 'offlineEnabled': false }
});

// Offline storage count
svc.on('locationCount').listen((data) {
  // { 'stored': 12 }
});

// Geofence enter / exit
svc.on('geofenceEvent').listen((data) {
  // { 'id': 'office', 'event': 'enter', 'latitude': ..., 'longitude': ..., 'distance': 45.2 }
});
```

### Geofencing

```dart
// Register a circular geofence
await BeTrackyBackgroundLocation.addGeofence(const Geofence(
  id: 'office',
  latitude: 12.345,
  longitude: 98.765,
  radiusMeters: 100,
));

// Remove one geofence
await BeTrackyBackgroundLocation.removeGeofence('office');

// Clear all geofences
await BeTrackyBackgroundLocation.clearGeofences();
```

Geofences are evaluated on every location fix using `Geolocator.distanceBetween`. State (inside / outside) is tracked in memory and `geofenceEvent` is fired only on transitions.

### Stored location query

```dart
// Query with optional date range
final locations = await BeTrackyBackgroundLocation.getStoredLocations(
  from: DateTime(2024, 1, 1),
  to: DateTime.now(),
  limit: 200,
);

final int count = await BeTrackyBackgroundLocation.getStoredLocationCount();

await BeTrackyBackgroundLocation.clearStoredLocations();
```

### `startService` parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `distanceFilter` | `int` | Yes | Minimum metres between location updates |
| `accuracy` | `LocationAccuracy` | Yes | Desired GPS accuracy |
| `startOnBoot` | `bool` | Yes | Restart service on device reboot |
| `foregroundService` | `bool` | Yes | Show persistent foreground notification |
| `url` | `String?` | No | Endpoint URL to POST locations to |
| `accessToken` | `String?` | No | Bearer token for your endpoint |
| `id` | `int?` | No | Location ID sent as `l_id` in the payload |
| `offlineEnabled` | `bool?` | No | Store every fix in SQLite. If `url` is also set, uploads in batches of 50; otherwise stores locally only (use `getStoredLocations()` to read) |
| `timeInterval` | `int?` | No | Minimum seconds between updates (0 = no limit) |
| `uploadFullData` | `bool?` | No | Include altitude, speed, heading, accuracy in payload |
| `customHeaders` | `Map<String, String>?` | No | Extra HTTP headers for every upload request |
| `maxRetries` | `int?` | No | Max retry attempts for failed uploads (default: 5) |

## Server payload format

```json
[
  {
    "l_id": 42,
    "latitude": 12.345678,
    "longitude": 98.765432,
    "actual_created_time": "2024-01-15T10:30:00.000Z",
    "altitude": 50.2,
    "speed": 1.5,
    "heading": 90.0,
    "accuracy": 5.0
  }
]
```

The `altitude`, `speed`, `heading`, and `accuracy` fields are only included when `uploadFullData: true`.

## Requesting permissions

```dart
import 'package:geolocator/geolocator.dart';
await Geolocator.requestPermission();
```

## Migration from 1.x

Remove the `betrackyToken` argument — it no longer exists:

```dart
// Before (1.x):
BeTrackyBackgroundLocation.startService(..., betrackyToken: 'e6fac1fd-...');

// After (2.x):
BeTrackyBackgroundLocation.startService(...);
```

Also rename `access_token` to `accessToken` if upgrading from 1.x.
