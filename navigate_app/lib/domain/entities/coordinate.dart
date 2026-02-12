import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';

/// ישות קואורדינטה
class Coordinate extends Equatable {
  final double lat;
  final double lng;
  final String utm; // מחרוזת UTM בת 12 ספרות

  const Coordinate({
    required this.lat,
    required this.lng,
    required this.utm,
  });

  /// יצירה מ-LatLng
  factory Coordinate.fromLatLng(LatLng latLng, String utm) {
    return Coordinate(
      lat: latLng.latitude,
      lng: latLng.longitude,
      utm: utm,
    );
  }

  /// המרה ל-LatLng
  LatLng toLatLng() => LatLng(lat, lng);

  /// העתקה עם שינויים
  Coordinate copyWith({
    double? lat,
    double? lng,
    String? utm,
  }) {
    return Coordinate(
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      utm: utm ?? this.utm,
    );
  }

  /// המרה ל-Map (Firestore)
  Map<String, dynamic> toMap() {
    return {
      'lat': lat,
      'lng': lng,
      'utm': utm,
    };
  }

  /// יצירה מ-Map (Firestore)
  factory Coordinate.fromMap(Map<String, dynamic> map) {
    return Coordinate(
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      utm: map['utm'] as String,
    );
  }

  @override
  List<Object?> get props => [lat, lng, utm];

  @override
  String toString() => 'Coordinate(lat: $lat, lng: $lng, utm: $utm)';
}
