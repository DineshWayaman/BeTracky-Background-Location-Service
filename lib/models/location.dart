class LocationDataModel {
  final int? id;
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? speed;
  final double? heading;
  final double? accuracy;
  final DateTime timestamp;

  LocationDataModel({
    this.id,
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.speed,
    this.heading,
    this.accuracy,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        "latitude": latitude,
        "longitude": longitude,
        "altitude": altitude,
        "speed": speed,
        "heading": heading,
        "accuracy": accuracy,
        "timestamp": timestamp.toIso8601String(),
      };

  factory LocationDataModel.fromJson(Map<String, dynamic> json) {
    return LocationDataModel(
      latitude: json["latitude"],
      longitude: json["longitude"],
      altitude: (json["altitude"] ?? 0.0).toDouble(),
      speed: (json["speed"] ?? 0.0).toDouble(),
      heading: (json["heading"] ?? 0.0).toDouble(),
      accuracy: (json["accuracy"] ?? 0.0).toDouble(),
      timestamp: DateTime.parse(json["timestamp"]),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  @override
  String toString() {
    return 'LocationDataModel(latitude: $latitude, longitude: $longitude, altitude: $altitude, speed: $speed, heading: $heading, accuracy: $accuracy, timestamp: $timestamp)';
  }
}
