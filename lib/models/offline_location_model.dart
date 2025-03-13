class OfflineLocationDataModel {
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  OfflineLocationDataModel({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
