# BeTracky Background Location Service

BeTracky Background Location Service is a Flutter package that provides background location tracking functionality. It uses `flutter_background_service`, `workmanager`, and `geolocator` to track the device's location even when the app is not in the foreground.

## Features

- Background location tracking
- Configurable distance filter and accuracy
- Start on boot option
- Foreground service support

## Getting started

To use this package, add `betracky_background_location` as a dependency in your `pubspec.yaml` file:


## Usage
- Import the package
```dart
  import 'package:betracky_background_location/betracky_background_location.dart';

    //Start the service
      BeTrackyBackgroundLocation.startService(
      distanceFilter: 10,
      accuracy: LocationAccuracy.high,
      startOnBoot: true,
      foregroundService: true,
    );

    // Stop the service
        BeTrackyBackgroundLocation.stopService();
```     

## Example
```dart
import 'dart:async';

import 'package:betracky_background_location/betracky_background_location.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationTest extends StatefulWidget {
  const LocationTest({super.key});

  @override
  State<LocationTest> createState() => _LocationTestState();
}

class _LocationTestState extends State<LocationTest> {
  LocationDataModel? _currentLocation;
  late StreamSubscription _streamSubscription;
  Future<void> requestPermissions() async {
    await Permission.location.request();
    await Permission.locationAlways.request(); // For background location
    await Permission.locationWhenInUse.request(); // For foreground location
  }

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    // Initialize background service
    var logger = Logger();


    _streamSubscription = FlutterBackgroundService().on("update").listen((locationData) {
      logger.e("Location Data: $locationData");
      setState(() {
        _currentLocation = LocationDataModel.fromJson(locationData!);
      });

    });



    initializeService();

  }

  Future<void> initializeService() async {
    await requestPermissions();

    BeTrackyBackgroundLocation.startService(
        distanceFilter: 0,
        accuracy: LocationAccuracy.best,
        startOnBoot: true,
        foregroundService: true,
    );

  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Location Tracker'),
      ),
      body: Center(
        child: _currentLocation == null
            ? CircularProgressIndicator()
            : Column(
          children: [
            Text(
              '📍 Location: ${_currentLocation!.latitude}, ${_currentLocation!.longitude}',
              style: TextStyle(fontSize: 20),
            ),
            ElevatedButton(onPressed: (){
              BeTrackyBackgroundLocation.stopService();
            }, child: Text('Stop Service'))
          ],
        ),
      ),
    );
  }
}



