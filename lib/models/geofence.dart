class Geofence {
  final String id;
  final double latitude;
  final double longitude;
  final double radiusMeters;

  const Geofence({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'latitude': latitude,
        'longitude': longitude,
        'radiusMeters': radiusMeters,
      };

  factory Geofence.fromJson(Map<String, dynamic> json) => Geofence(
        id: json['id'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        radiusMeters: (json['radiusMeters'] as num).toDouble(),
      );

  @override
  String toString() =>
      'Geofence(id: $id, lat: $latitude, lng: $longitude, radius: ${radiusMeters}m)';
}
