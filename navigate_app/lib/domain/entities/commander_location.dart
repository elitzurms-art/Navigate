import 'package:latlong2/latlong.dart';

/// מיקום מפקד אחר על המפה
class CommanderLocation {
  final String userId;
  final String name;
  LatLng position;
  DateTime lastUpdate;

  CommanderLocation({
    required this.userId,
    required this.name,
    required this.position,
    required this.lastUpdate,
  });

  factory CommanderLocation.fromFirestore(String docId, Map<String, dynamic> data) {
    return CommanderLocation(
      userId: data['userId'] as String? ?? docId,
      name: data['name'] as String? ?? '',
      position: LatLng(
        (data['latitude'] as num?)?.toDouble() ?? 0,
        (data['longitude'] as num?)?.toDouble() ?? 0,
      ),
      lastUpdate: _parseDateTime(data['updatedAt']) ?? DateTime.now(),
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    try {
      return (value as dynamic).toDate() as DateTime;
    } catch (_) {
      return null;
    }
  }
}
