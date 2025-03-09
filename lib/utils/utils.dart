import '../models/location.dart';

class WaypointUtils {
  static LocationDataModel processLocationData(Map<String, dynamic> json) {
    return LocationDataModel(
      latitude: json["latitude"],
      longitude: json["longitude"],
      altitude: json["altitude"] ?? 0.0,
      speed: json["speed"] ?? 0.0,
      heading: json["heading"] ?? 0.0,
      accuracy: json["accuracy"] ?? 0.0,
      timestamp: DateTime.parse(json["timestamp"]),
    );
  }
}
