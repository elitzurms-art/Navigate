/// Known tower position from the local database.
class TowerLocation {
  final int mcc;
  final int mnc;
  final int lac;
  final int cid;
  final double lat;
  final double lon;

  /// Estimated range of the tower in meters.
  final int range;

  /// Radio type string (GSM, LTE, UMTS, NR, CDMA).
  final String type;

  const TowerLocation({
    required this.mcc,
    required this.mnc,
    required this.lac,
    required this.cid,
    required this.lat,
    required this.lon,
    required this.range,
    required this.type,
  });

  factory TowerLocation.fromMap(Map<String, dynamic> map) {
    return TowerLocation(
      mcc: map['mcc'] as int,
      mnc: map['mnc'] as int,
      lac: map['lac'] as int,
      cid: map['cid'] as int,
      lat: (map['lat'] as num).toDouble(),
      lon: (map['lon'] as num).toDouble(),
      range: map['range'] as int,
      type: map['type'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'mcc': mcc,
      'mnc': mnc,
      'lac': lac,
      'cid': cid,
      'lat': lat,
      'lon': lon,
      'range': range,
      'type': type,
    };
  }

  @override
  String toString() =>
      'TowerLocation(mcc: $mcc, mnc: $mnc, lac: $lac, cid: $cid, '
      'lat: $lat, lon: $lon, range: ${range}m)';
}
