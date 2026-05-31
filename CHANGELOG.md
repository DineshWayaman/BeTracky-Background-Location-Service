## 2.1.1

**Bug fixes:**
* `offlineEnabled: true` now stores locations in SQLite even when no `url` is configured. Previously the local DB write was skipped because the URL guard fired first, making `getStoredLocations()` always return empty for local-only usage.
* `startService` now throws a `StateError` immediately if location permission is denied, instead of starting silently and producing no updates.
* Added a `debugPrint` warning when `foregroundService: true` on Android, reminding developers to grant `POST_NOTIFICATIONS` at runtime (Android 13+). Without it the foreground notification is suppressed and the OS will kill the service when the app is closed.
* README: Added "Runtime permissions (critical)" section with explicit code showing `Permission.notification.request()` must be called before `startService`.

## 2.1.0

**New features:**
* **Retry queue with exponential backoff** — failed uploads are stored in a local SQLite table and retried automatically (1 min → 2 min → 4 min → … → max 60 min). New `maxRetries` parameter controls the limit. Workmanager runs a periodic retry task every 15 minutes when connected.
* **Upload status & service state callbacks** — three new stream events: `uploadStatus` `{success, uploaded, pending}`, `serviceStatus` `{running, tracking, offlineEnabled}`, and `locationCount` `{stored}`. New `getStatus()` method for one-shot status queries.
* **Pause / Resume tracking** — `pauseTracking()` and `resumeTracking()` suspend/restore the location stream without losing configuration or stopping the service. `isTracking()` returns the current state.
* **Time-interval filter** — new `timeInterval` parameter caps update frequency by time (e.g. `timeInterval: 30` = at most one update every 30 seconds), complementing the existing distance filter.
* **Upload full location fields** — new `uploadFullData: true` flag adds `altitude`, `speed`, `heading`, and `accuracy` to the server payload. These fields are now always stored in the local SQLite database (schema v2 migration included).
* **Custom HTTP headers** — new `customHeaders: Map<String, String>` parameter adds arbitrary headers to every upload request, enabling any backend auth scheme.
* **Circular geofencing** — `addGeofence(Geofence)`, `removeGeofence(id)`, and `clearGeofences()` manage circular regions evaluated on every location fix. Entry and exit fire `geofenceEvent` stream events with `{id, event, latitude, longitude, distance}`. No new native dependencies — pure Dart using `Geolocator.distanceBetween`.
* **Stored location query API** — `getStoredLocations({from, to, limit})`, `getStoredLocationCount()`, and `clearStoredLocations()` expose the local SQLite database for analytics and route replay.

## 2.0.0

**Breaking changes:**
* Removed `betrackyToken` parameter from `startService` — no registration required.
* Minimum Flutter SDK bumped to 3.29.0.

**Dependency updates:**
* `workmanager` upgraded from 0.5.2 to 0.9.0 (enum names changed to camelCase).
* `geolocator` upgraded from 13.0.2 to 14.0.2 (`getCurrentPosition` now uses `LocationSettings`).
* Removed unused `flutter_foreground_task` dependency.
* Updated `http` to 1.6.0, `shared_preferences` to 2.5.5, `sqflite` to 2.4.2+1, `path` to 1.9.1.

**Bug fixes:**
* `distanceFilter` and `accuracy` parameters passed to `startService` are now correctly applied to the geolocator stream (previously hardcoded).
* Removed force-unwrap crashes (`url!`, `id!`) — replaced with safe null guards.
* Added 30-second timeout to all HTTP upload requests.
* Fixed SQL parameter binding in `deleteBatchLocations` to use `whereArgs` instead of string interpolation.
* Wrapped the position stream listener in a top-level try/catch to prevent silent crashes.
* Removed `print()` calls from library code — replaced with `debugPrint()`.

**Package improvements:**
* Added `repository`, `issue_tracker`, and `topics` to `pubspec.yaml`.
* Added an `example/` app.
* Removed dead code: `OfflineLocationDataModel` and stray `lib/test` draft file.
* Added unit tests for `LocationDataModel` and `WaypointUtils`.

## 1.0.3

* Minor stability improvements.

## 1.0.2

* Offline mode batch upload improvements.

## 1.0.1

* iOS background service configuration fixes.

## 1.0.0

* Initial release of BeTracky Background Location Service.
* Background location tracking with configurable distance filter and accuracy.
* Start on boot and foreground service support.
* Offline mode: store locations locally and upload in batches of 50 when back online.
* Upload locations to a custom endpoint with optional Bearer token authentication.
