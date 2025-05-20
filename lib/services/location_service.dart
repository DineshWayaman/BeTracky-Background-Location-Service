import 'dart:async';
import 'dart:convert';
import 'package:betracky_background_location/models/location.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:workmanager/workmanager.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:betracky_background_location/utils/database_helper.dart';

class BeTrackyBackgroundLocation {
  static final _service = FlutterBackgroundService();
  static StreamSubscription<Position>? _positionStreamSubscription;
  static String beTrackyToken = "e6fac1fd-1bc0-449b-a562-22b9b916e3098jhA";

  static Future<void> startService({
    required int distanceFilter,
    required LocationAccuracy accuracy,
    required bool startOnBoot,
    required bool foregroundService,
    String? url,
    String? access_token,
    bool? offlineEnabled,
    int? id,
    required String betrackyToken,
  }) async {
    if (betrackyToken.isEmpty) {
      throw Exception("BeTracky token can't be null.");
    } else if (betrackyToken != beTrackyToken) {
      throw Exception("BeTracky token invalid");
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
    await _service.startService();
    // Pass the URL and access token to the service
    // Store offlineEnabled in SharedPreferences
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool("offlineEnabled", offlineEnabled ?? false);
    await prefs.setInt("id", id ?? 1112333322111);

    _service.invoke("setParams", {
      "url": url,
      "access_token": access_token,
      "offlineEnabled": offlineEnabled
    });
    Workmanager().initialize(callbackDispatcher);
  }

  static Future<void> stopService() async {
    _positionStreamSubscription?.cancel();
    _service.invoke("stopService");
  }

  static void onStart(ServiceInstance service) async {

    DartPluginRegistrant.ensureInitialized();

    if(service is AndroidServiceInstance){
      try{
        await service.setForegroundNotificationInfo(title: 'Location Tracking', content: "Tracking Your Location in the Background");
      }catch(e){
        print("Foreground Notification Error: $e");
      }
    }

    SharedPreferences prefs = await SharedPreferences.getInstance();
    DatabaseHelper dbHelper = DatabaseHelper();
    // Retrieve stored values
    String? url = prefs.getString("url");
    String? accessToken = prefs.getString("access_token");
    bool? offlineEnabled = prefs.getBool("offlineEnabled");
    int? id = prefs.getInt("id");

    // Listen for parameters
    service.on("setParams").listen((data) {
      if (data != null && data is Map<String, dynamic>) {
        String? newUrl = data["url"] as String?;
        String? newAccessToken = data["access_token"] as String?;
        bool? newOfflineEnabled = data["offlineEnabled"] as bool?;

        // Use saved values if new ones are null
        newUrl ??= url;
        newAccessToken ??= accessToken;
        newOfflineEnabled ??= offlineEnabled;

        // Update stored values only if different
        if (newUrl != null) {
          if (newUrl != url ||
              newAccessToken != accessToken ||
              newOfflineEnabled != offlineEnabled) {
            prefs.setString("url", newUrl);
            if (newAccessToken != null) {
              prefs.setString("access_token", newAccessToken);
            }
            if (newOfflineEnabled != null) {
              prefs.setBool("offlineEnabled", newOfflineEnabled);
            }
            url = newUrl;
            accessToken = newAccessToken;
            offlineEnabled = newOfflineEnabled;
          }
        }
      }
    });

    service.on("stopService").listen((_) {
      _positionStreamSubscription?.cancel();
      service.stopSelf();
    });

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      ),
    ).listen((Position position) async {
      print("📍 New Location: ${position.latitude}, ${position.longitude}");

      final locationData = LocationDataModel(
        latitude: position.latitude,
        longitude: position.longitude,
        altitude: position.altitude,
        speed: position.speed,
        heading: position.heading,
        accuracy: position.accuracy,
        timestamp: DateTime.now(),
      );

      service.invoke("update", locationData.toJson());

      print("Offline: ${offlineEnabled}");
      if (offlineEnabled == true) {
        try {
          await dbHelper.insertLocation(locationData);
        } catch (e) {
          print("Error LocalDB: $e");
        }

        final locations = await dbHelper.getBatchLocation(50);
        print('LocationsBatch: ${locations.toString()}');

        if (locations.length >= 50) {
          if (url != null) {
            print("url : $url");
            await uploadLocation(locations, url!, accessToken, id!);
          }
        }
      } else {
        if (url != null) {
          print("url : $url");
          await uploadLocationOnline(locationData, url!, accessToken, id!);
        }
      }
    });
  }

  static Future<void> uploadLocation(List<LocationDataModel> locations,
      String url, String? access_token, int? id) async {
    // Upload location data to server

    if (id == 1112333322111) {
      id = DateTime.now().millisecondsSinceEpoch;
    }

    print("ID: $id");

    print("url2 : $url");
    print('Uploading location data to server...');
    List<Map<String, dynamic>> data = locations
        .map((location) => {
              'l_id': id,
              'latitude': location.latitude,
              'longitude': location.longitude,
              'actual_created_time': location.timestamp.toIso8601String(),
            })
        .toList();

    try {
      var headers = {
        'Content-Type': 'application/json',
      };

      if (access_token != null) {
        headers['Authorization'] = 'Bearer $access_token';
      }

      var response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(data),
      );

      if (response.statusCode == 200) {
        print('Data uploaded successfully.');
        // Delete uploaded records from the database
        DatabaseHelper dbHelper = DatabaseHelper();
        final ids = locations
            .map((location) => location.id)
            .where((id) => id != null)
            .cast<int>()
            .toList();
        await dbHelper.deleteBatchLocations(ids);
      } else {
        print('Failed to upload data: ${response.statusCode}');
      }
    } catch (e) {
      print('Error: $e');
    }
  }

  static Future<void> uploadLocationOnline(LocationDataModel location,
      String url, String? access_token, int? id) async {
    // Upload location data to server
    print("url2 : $url");
    print('Uploading location data to server...');

    if (id == 1112333322111) {
      id = DateTime.now().millisecondsSinceEpoch;
    }
    print("IDSSD: $id");
    List<Map<String, dynamic>> data = [
      {
        'l_id': id,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'actual_created_time': location.timestamp.toIso8601String(),
      }
    ];

    try {
      var headers = {
        'Content-Type': 'application/json',
      };

      if (access_token != null) {
        headers['Authorization'] = 'Bearer $access_token';
      }

      var response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(data),
      );

      if (response.statusCode == 200) {
        print('Data uploaded successfully.');
      } else {
        print('Failed to upload data: ${response.body}');
      }
    } catch (e) {
      print('Error: $e');
    }
  }

  static Future<bool> onBackground(ServiceInstance service) async {
    return true;
  }
}

void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );

    print("Background location: ${position.latitude}, ${position.longitude}");
    return Future.value(true);
  });
}
