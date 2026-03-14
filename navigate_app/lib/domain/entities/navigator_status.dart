/// סטטוס מנווט — נתוני system check ומיקום
class NavigatorStatus {
  final bool isConnected;
  final bool hasReported;
  final int batteryLevel;
  final bool hasGPS;
  final int receptionLevel;
  final double? latitude;
  final double? longitude;
  final String positionSource;
  final DateTime? positionUpdatedAt;
  final double gpsAccuracy;
  final String mapsStatus;
  final bool hasMicrophonePermission;
  final bool hasPhonePermission;
  final bool hasDNDPermission;

  NavigatorStatus({
    required this.isConnected,
    this.hasReported = false,
    required this.batteryLevel,
    required this.hasGPS,
    this.receptionLevel = 0,
    this.latitude,
    this.longitude,
    this.positionSource = 'gps',
    this.positionUpdatedAt,
    this.gpsAccuracy = -1,
    this.mapsStatus = 'notStarted',
    this.hasMicrophonePermission = false,
    this.hasPhonePermission = false,
    this.hasDNDPermission = false,
  });

  bool get mapsReady => mapsStatus == 'completed';

  factory NavigatorStatus.fromFirestore(Map<String, dynamic> data) {
    return NavigatorStatus(
      isConnected: data['isConnected'] as bool? ?? false,
      hasReported: true,
      batteryLevel: data['batteryLevel'] as int? ?? -1,
      hasGPS: data['hasGPS'] as bool? ?? false,
      receptionLevel: data['receptionLevel'] as int? ?? 0,
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      positionSource: data['positionSource'] as String? ?? 'gps',
      positionUpdatedAt: _parseDateTime(data['positionUpdatedAt'] ?? data['updatedAt']),
      gpsAccuracy: (data['gpsAccuracy'] as num?)?.toDouble() ?? -1,
      mapsStatus: data['mapsStatus'] as String? ?? 'notStarted',
      hasMicrophonePermission: data['hasMicrophonePermission'] as bool? ?? false,
      hasPhonePermission: data['hasPhonePermission'] as bool? ?? false,
      hasDNDPermission: data['hasDNDPermission'] as bool? ?? false,
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    // Firestore Timestamp
    try {
      return (value as dynamic).toDate() as DateTime;
    } catch (_) {
      return null;
    }
  }
}
