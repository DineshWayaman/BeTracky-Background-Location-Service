import 'dart:async';

import 'package:betracky_background_location/betracky_background_location.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BeTracky Feature Test',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const FeatureTestPage(),
    );
  }
}

class FeatureTestPage extends StatefulWidget {
  const FeatureTestPage({super.key});
  @override
  State<FeatureTestPage> createState() => _FeatureTestPageState();
}

class _FeatureTestPageState extends State<FeatureTestPage> {
  // Service state
  bool _isRunning = false;
  bool _isPaused = false;

  // F2: stream event log
  final List<String> _log = [];

  // F2: latest values from streams
  LocationDataModel? _lastLoc;
  int _pendingUploads = 0;
  int _storedCount = 0;

  // F7: last geofence event
  String _geofenceStatus = '—';

  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    // Reconnect to running service if app was reopened after a kill
    BeTrackyBackgroundLocation.getStatus().then((status) {
      if (mounted) {
        setState(() {
          _isRunning = status['isRunning'] as bool? ?? false;
          _isPaused = !(status['isTracking'] as bool? ?? true);
          _pendingUploads = status['pendingUploads'] as int? ?? 0;
        });
      }
    });
    final svc = FlutterBackgroundService();

    _subs.addAll([
      // F2: live location
      svc.on('update').listen((data) {
        if (data == null) return;
        setState(() {
          _lastLoc = LocationDataModel.fromJson(data);
          _addLog('📍 update: ${_lastLoc!.latitude.toStringAsFixed(5)}, '
              '${_lastLoc!.longitude.toStringAsFixed(5)} '
              '| alt=${_lastLoc!.altitude?.toStringAsFixed(1)} '
              '| spd=${_lastLoc!.speed?.toStringAsFixed(2)}');
        });
      }),

      // F2: upload status
      svc.on('uploadStatus').listen((data) {
        if (data == null) return;
        setState(() {
          _pendingUploads = (data['pending'] as int?) ?? 0;
          final ok = data['success'] as bool? ?? false;
          _addLog('${ok ? '✅' : '❌'} uploadStatus: '
              'uploaded=${data['uploaded']} pending=$_pendingUploads '
              '${data['error'] ?? ''}');
        });
      }),

      // F2: service status
      svc.on('serviceStatus').listen((data) {
        if (data == null) return;
        setState(() => _addLog(
            '⚙️  serviceStatus: running=${data['running']} '
            'tracking=${data['tracking']}'));
      }),

      // F2: location count (offline mode)
      svc.on('locationCount').listen((data) {
        if (data == null) return;
        setState(() {
          _storedCount = (data['stored'] as int?) ?? 0;
          _addLog('💾 locationCount: stored=$_storedCount');
        });
      }),

      // F7: geofence events
      svc.on('geofenceEvent').listen((data) {
        if (data == null) return;
        setState(() {
          _geofenceStatus =
              '${data['event'].toString().toUpperCase()} "${data['id']}" '
              '(${(data['distance'] as double?)?.toStringAsFixed(0) ?? '?'}m away)';
          _addLog('🔵 geofence: $_geofenceStatus');
        });
      }),
    ]);
  }

  void _addLog(String msg) {
    _log.insert(0, msg);
    if (_log.length > 30) _log.removeLast();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _requestPermissions() async {
    await [
      Permission.location,
      Permission.locationAlways,
      Permission.notification,
    ].request();
    await Geolocator.requestPermission();
  }

  Future<void> _start() async {
    await _requestPermissions();

    // Register a geofence at the current position (F7)
    final pos = await Geolocator.getCurrentPosition();
    // Place fence 20 m north so we can observe entry/exit by moving
    await BeTrackyBackgroundLocation.addGeofence(Geofence(
      id: 'test_zone',
      latitude: pos.latitude + 0.00018, // ~20 m north
      longitude: pos.longitude,
      radiusMeters: 30,
    ));

    await BeTrackyBackgroundLocation.startService(
      distanceFilter: 0,
      accuracy: LocationAccuracy.high,
      startOnBoot: false,
      foregroundService: true,
      timeInterval: 5,      // at most one update per 5 s
      uploadFullData: true, // include altitude, speed, heading
      offlineEnabled: true, // store locally so we can verify DB count
      maxRetries: 3,
    );

    setState(() {
      _isRunning = true;
      _isPaused = false;
    });
    _addLog('▶️  service started');
  }

  Future<void> _stop() async {
    await BeTrackyBackgroundLocation.stopService();
    setState(() {
      _isRunning = false;
      _isPaused = false;
    });
    _addLog('⏹  service stopped');
  }

  Future<void> _pause() async {
    await BeTrackyBackgroundLocation.pauseTracking(); // F3
    setState(() => _isPaused = true);
    _addLog('⏸  tracking paused (F3)');
  }

  Future<void> _resume() async {
    await BeTrackyBackgroundLocation.resumeTracking(); // F3
    setState(() => _isPaused = false);
    _addLog('▶️  tracking resumed (F3)');
  }

  Future<void> _refreshCount() async {
    // F8: query API
    final count = await BeTrackyBackgroundLocation.getStoredLocationCount();
    final status = await BeTrackyBackgroundLocation.getStatus(); // F2
    setState(() {
      _storedCount = count;
      _pendingUploads = (status['pendingUploads'] as int?) ?? 0;
      _addLog('🔍 getStoredLocationCount=$count | getStatus=${status['isTracking']}');
    });
  }

  Future<void> _clearStored() async {
    await BeTrackyBackgroundLocation.clearStoredLocations(); // F8
    setState(() {
      _storedCount = 0;
      _addLog('🗑  clearStoredLocations() called (F8)');
    });
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BeTracky v2.1.0 — Feature Test'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: Column(
        children: [
          // Status bar
          Container(
            color: _isRunning
                ? (_isPaused ? Colors.orange.shade100 : Colors.green.shade100)
                : Colors.grey.shade100,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  _isRunning
                      ? (_isPaused ? Icons.pause_circle : Icons.check_circle)
                      : Icons.stop_circle,
                  color: _isRunning
                      ? (_isPaused ? Colors.orange : Colors.green)
                      : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  _isRunning
                      ? (_isPaused ? 'PAUSED' : 'TRACKING')
                      : 'STOPPED',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text('💾 $_storedCount  |  ⏳ $_pendingUploads pending'),
              ],
            ),
          ),

          // Location display (F5: shows full fields)
          if (_lastLoc != null)
            Container(
              color: Colors.teal.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'lat=${_lastLoc!.latitude.toStringAsFixed(5)} '
                      'lng=${_lastLoc!.longitude.toStringAsFixed(5)}\n'
                      'alt=${_lastLoc!.altitude?.toStringAsFixed(1)}m  '
                      'spd=${_lastLoc!.speed?.toStringAsFixed(2)}m/s  '
                      'hdg=${_lastLoc!.heading?.toStringAsFixed(0)}°',
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
            ),

          // Geofence status (F7)
          Container(
            color: Colors.blue.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.radio_button_checked, size: 16, color: Colors.blue),
                const SizedBox(width: 6),
                Text('Geofence: $_geofenceStatus',
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),

          // Action buttons
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _isRunning ? _stop : _start,
                  icon: Icon(_isRunning ? Icons.stop : Icons.play_arrow),
                  label: Text(_isRunning ? 'Stop' : 'Start'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRunning ? Colors.red : Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
                if (_isRunning) ...[
                  ElevatedButton.icon(
                    onPressed: _isPaused ? _resume : _pause,
                    icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
                    label: Text(_isPaused ? 'Resume' : 'Pause'), // F3
                  ),
                ],
                OutlinedButton.icon(
                  onPressed: _refreshCount,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Refresh'), // F8
                ),
                OutlinedButton.icon(
                  onPressed: _clearStored,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Clear DB'), // F8
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Event log (F2: all stream events shown live)
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              itemCount: _log.length,
              itemBuilder: (_, i) => Text(
                _log[i],
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
