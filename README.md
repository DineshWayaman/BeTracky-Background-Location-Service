# BeTracky Background Location Service

BeTracky Background Location Service is a Flutter package that provides background location tracking functionality. It can use to track the device's location even when the app is not in the foreground.

## Features

- Background location tracking
- Configurable distance filter and accuracy
- Start on boot option
- Foreground service support
- Offline mode to store locations locally when offline and upload them in batches when back online
- Upload locations to a custom endpoint
- Upload locations to BeTracky API
- Custom location id support

## Getting started

To use this package, add `betracky_background_location` as a dependency in your `pubspec.yaml` file:


## Usage
- Import the package
- You can send `url` and `access_token` if you have your own backend endpoint to upload locations. This will help you to upload locations even when the app is closed.
- The `offlineEnabled` mode allows the app to store locations locally when offline and upload them in batches when back online.
- The `url` and `access_token` and `id` are not mandatory. If you do not use a token, just pass the `url`. If you use a token, it should be a Bearer token. If you pass an id it will be sent to the endpoint as the location id otherwise it will generate id.(user_id, device_id, journey_id etc)


- Start the service by calling the `startService` method. You can pass the following parameters:
  - `distanceFilter`: The minimum distance between location updates in meters. Default is 0.
  - `accuracy`: The desired accuracy for location updates. Default is `LocationAccuracy.high`.
  - `startOnBoot`: Whether to start the service when the device boots up. Default is `false`.
  - `foregroundService`: Whether to run the service as a foreground service. Default is `false`.
  - `offlineEnabled`: Whether to store locations locally when offline and upload them in batches when back online. Default is `false`.
  - `url`: The endpoint URL to upload locations. Optional.
  - `access_token`: The access token to authenticate with the endpoint. Optional.
  - `id`: The location id to send to the endpoint. Optional.
  - `betrackyToken`: The token to authenticate with BeTracky API. This is mandatory.
```dart
import 'package:betracky_background_location/betracky_background_location.dart';

    try {
        BeTrackyBackgroundLocation.startService(
        distanceFilter: 0,
        accuracy: LocationAccuracy.high,
        startOnBoot: true,
        foregroundService: true,
        url: your_endpoint, // Optional
        access_token: your_endpoint_access_token, // Optional
        id: 5, // Optional - This is the location id that will be sent to the endpoint
        offlineEnabled: true, // Optional
        betrackyToken: "e6fac1fd-1bc0-449b-a562-22b9b916e3098jhA",
      );
    } catch (e) {
      print('ErrorBetracky: $e');
    }
    
```

- Stop the service by calling the `stopService` method.
```dart
    BeTrackyBackgroundLocation.stopService();
```
    
- If you enabled online mode, this is the format your endpoint should accept for the payload: `l_id`, `latitude`, `longitude`, `actual_created_time` are the fields that will be sent to the endpoint.
```json
    [
      {
        "l_id": 5,
        "latitude": 12.345678,
        "longitude": 98.765432,
        "actual_created_time": "2023-10-10T10:10:10.000Z"
      }
    ]
```
- If offline mode is enabled, the app will upload 50 bulk locations in the following format:
```json
      [
          {
            "l_id": 5,
            "latitude": 12.345678,
            "longitude": 98.765432,
            "actual_created_time": "2023-10-10T10:10:10.000Z"
          },
          {
            "l_id": 5,
            "latitude": 12.345678,
            "longitude": 98.765432,
            "actual_created_time": "2023-10-10T10:10:10.000Z"
          },
          ...
      ]

```   

- Install permission_handler and geolocator packages to request location permissions and get the device's location.
```yaml
dependencies:
  permission_handler: latest_version
  geolocator: latest_version
```

- You need to add following permissions in your `AndroidManifest.xml` file:
```xml
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />

<!--  Inside <application>-->
    <application
<!--     Add this service-->
      <service
      android:name="com.transistorsoft.flutter.backgroundfetch.HeadlessTask"
      android:permission="android.permission.BIND_JOB_SERVICE"
      android:exported="true"/>

    </application>

```

- You need to add following permissions in your `Info.plist` file:
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




## Example
```dart
import 'dart:async';
import 'dart:convert';

import 'package:betracky_background_location/models/location.dart';
import 'package:betracky_background_location/services/location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:globetrack/test/noti_service.dart';
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;

class Test extends StatefulWidget {
  const Test({super.key});

  @override
  State<Test> createState() => _TestState();
}

class _TestState extends State<Test> {
  var logger = Logger();
  LocationDataModel? _currentLocation;
  late StreamSubscription _streamSubscription;
  final NotiService notiService = NotiService();


  Future<void> requestPermissions() async {
    await Permission.location.request();
    await Permission.locationAlways.request(); // For background location
    await Permission.locationWhenInUse.request(); // For foreground location
  }

  @override
  void initState() {
    // TODO: implement initState
    super.initState();

    initializeService();
    _streamSubscription = FlutterBackgroundService().on("update").listen((locationData) {
      logger.e("Location Data: $locationData");
      setState(() {
        _currentLocation = LocationDataModel.fromJson(locationData!);
      });

    });
  }

  Future<void> uploadLocation(LocationDataModel locationData) async {
    var logger = Logger();

    // Upload location data to server
    String baseUrl = "https://api.betracky.com";
    String endpoint = "/api/v1/locations";
    String url = "$baseUrl$endpoint";
    String access_token = "your_access_token";

    List<Map<String, dynamic>> data = [
      {
        'journey_id': 5,
        'latitude': locationData.latitude,
        'longitude': locationData.longitude,
        'actual_created_time': locationData.timestamp.toIso8601String(),
      }
    ];


    try{
      var response = await http.post(
        Uri.parse(url),
        headers: {
          "Authorization": "Bearer $access_token",
          'Content-Type': 'application/json',
        },
        body: jsonEncode(data),
      );

      logger.e("Response: ${response.body}");

      if (response.statusCode == 200) {
        print('Data uploaded successfully.');
        notiService.showNotification(title: 'Location Uploaded', body: 'Your location :. ${locationData.timestamp}');
      }else{
        print('Failed to upload data: ${response.statusCode}');
      }
    }catch(e){
      print('Error: $e');
    }




  }


  Future<void> initializeService() async {
    await requestPermissions();


    FlutterBackgroundService().on("update").listen((locationData) {
      if (locationData != null) {
        var logger = Logger();
        logger.e("Location Data: $locationData");
        LocationDataModel location = LocationDataModel.fromJson(locationData);
        // uploadLocation(location);
      }
    });

   try{
     BeTrackyBackgroundLocation.startService(
       distanceFilter: 0,
       accuracy: LocationAccuracy.high,
       startOnBoot: true,
       foregroundService: true,
       offlineEnabled: false, // Optional
       url: "your_endpoint", // Optional
       access_token: "your_endpoint_access_token", // Optional
       id: your id, // Optional
       betrackyToken: "e6fac1fd-1bc0-449b-a562-22b9b916e3098jhA", // use this key 
     );
  }catch(e){
    logger.e('ErrorBetracky: $e');
  }

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




