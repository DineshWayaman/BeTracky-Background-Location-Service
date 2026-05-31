# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
flutter pub get          # Install dependencies
flutter analyze          # Lint (uses analysis_options.yaml with flutter_lints)
flutter test             # Run all tests
flutter test test/betracky_background_location_test.dart  # Run a single test file
```

## Architecture

This is a **Flutter package** (not an app) that provides background location tracking with optional server upload. It is published to pub.dev as `betracky_background_location`.

### Entry point

`lib/betracky_background_location.dart` re-exports three public surfaces:
- `services/location_service.dart` — the main `BeTrackyBackgroundLocation` static class
- `models/location.dart` — `LocationDataModel`
- `utils/utils.dart` — `WaypointUtils`

### Service lifecycle

`BeTrackyBackgroundLocation` (in `lib/services/location_service.dart`) is entirely static and drives two platform plugins:

- **`flutter_background_service`** — runs `onStart` (Android) / `onBackground` (iOS) in a separate isolate, streams live location updates via `service.invoke("update", ...)` that callers subscribe to with `FlutterBackgroundService().on("update")`.
- **`workmanager`** — initialized with `callbackDispatcher` (a top-level function at the bottom of the file, required by the plugin) for boot-start scheduling.

`startService` validates the hardcoded `betrackyToken` before configuring either plugin. Parameters (`url`, `access_token`, `offlineEnabled`, `id`) are persisted via `SharedPreferences` and also forwarded into the running isolate via `service.invoke("setParams", ...)` because isolates don't share memory.

### Upload modes

Two distinct upload paths exist inside the position stream listener in `onStart`:

| Mode | Trigger | Upload unit |
|------|---------|-------------|
| **Online** (`offlineEnabled: false`) | Every position fix | Single location JSON array |
| **Offline** (`offlineEnabled: true`) | When local DB batch reaches 50 rows | 50-location JSON array; rows deleted on 200 response |

Both modes POST to the caller-supplied `url` with optional `Authorization: Bearer <token>` header. Payload shape: `[{"l_id", "latitude", "longitude", "actual_created_time"}]`.

### Local database

`DatabaseHelper` (`lib/utils/database_helper.dart`) is a singleton wrapping `sqflite`. It stores `(id, latitude, longitude, timestamp)` in `locations.db`. Only used in offline mode. The `id` column is used to delete uploaded batches via `deleteBatchLocations(List<int> ids)`.

### Token

The package validates `betrackyToken` against a hardcoded value at `location_service.dart:16`. Passing a wrong or empty token throws an exception before the service starts.
