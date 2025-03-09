import 'dart:async';

import 'package:betracky_background_location/models/location.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:workmanager/workmanager.dart';

class BeTrackyBackgroundLocation {
  static final _service = FlutterBackgroundService();

  static Future<void> startService({
    required int distanceFilter,
    required LocationAccuracy accuracy,
    required bool startOnBoot,
    required bool foregroundService,
}) async {

    await _service.configure(
        iosConfiguration: IosConfiguration(
            onBackground: onBackground,
            autoStart: startOnBoot,
        ),
        androidConfiguration: AndroidConfiguration(
            onStart: onStart,
            isForegroundMode: foregroundService,
          autoStart: startOnBoot,
        )
    );
    _service.startService();
    Workmanager().initialize(callbackDispatcher);
  }

  static Future<void> stopService() async {
    _service.invoke("stopService");
  }

  static void onStart(ServiceInstance service) async {
    service.on("stopService").listen((_){
      service.stopSelf();
    });

    Timer.periodic(const Duration(seconds: 10), (timer) async {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

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


    });

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