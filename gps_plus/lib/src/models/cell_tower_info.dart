/// Represents a visible cell tower as reported by the device.
class CellTowerInfo {
  /// Cell ID
  final int cid;

  /// Location Area Code (GSM/UMTS) or Tracking Area Code (LTE/NR)
  final int lac;

  /// Mobile Country Code
  final int mcc;

  /// Mobile Network Code
  final int mnc;

  /// Received Signal Strength Indicator in dBm
  final int rssi;

  /// Radio access technology type
  final CellType type;

  /// Timestamp when this measurement was taken
  final DateTime timestamp;

  const CellTowerInfo({
    required this.cid,
    required this.lac,
    required this.mcc,
    required this.mnc,
    required this.rssi,
    required this.type,
    required this.timestamp,
  });

  factory CellTowerInfo.fromMap(Map<String, dynamic> map) {
    return CellTowerInfo(
      cid: map['cid'] as int,
      lac: map['lac'] as int,
      mcc: map['mcc'] as int,
      mnc: map['mnc'] as int,
      rssi: map['rssi'] as int,
      type: CellType.fromString(map['type'] as String),
      timestamp: map['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'cid': cid,
      'lac': lac,
      'mcc': mcc,
      'mnc': mnc,
      'rssi': rssi,
      'type': type.name,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  @override
  String toString() =>
      'CellTowerInfo(cid: $cid, lac: $lac, mcc: $mcc, mnc: $mnc, '
      'rssi: $rssi, type: ${type.name})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CellTowerInfo &&
          cid == other.cid &&
          lac == other.lac &&
          mcc == other.mcc &&
          mnc == other.mnc;

  @override
  int get hashCode => Object.hash(cid, lac, mcc, mnc);
}

/// Radio access technology types.
enum CellType {
  gsm,
  cdma,
  umts,
  lte,
  nr;

  static CellType fromString(String value) {
    return CellType.values.firstWhere(
      (e) => e.name == value.toLowerCase(),
      orElse: () => CellType.gsm,
    );
  }
}
