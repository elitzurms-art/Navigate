import 'dart:math';

/// פילטר קלמן דו-ממדי להחלקת מיקום GPS
///
/// וקטור מצב: [x, y, vx, vy] — מיקום ומהירות במטרים מקומיים
/// (יחסית לנקודת ייחוס — המדידה הראשונה)
class PositionKalmanFilter {
  // --- Reference point (first measurement) ---
  double? _refLat;
  double? _refLng;

  // --- State vector [x, y, vx, vy] ---
  final List<double> _x = [0, 0, 0, 0];

  // --- Covariance matrix P (4×4, row-major) ---
  final List<double> _P = List.filled(16, 0);

  DateTime? _lastTimestamp;

  /// Process noise intensity — acceleration variance (m/s²)²
  /// Adaptive: scales with GPS accuracy. Stationary: 0.001 (ZUPT override).
  static const double _qBase = 0.5;
  static const double _qStationary = 0.001;
  static const double _referenceAccuracy = 10.0;
  static const double _qMinScale = 0.1;
  static const double _qMaxScale = 2.0;
  double _q = _qBase;
  bool _isStationary = false;
  double _lastMeasurementAccuracy = 10.0;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// Process measurement, return filtered position + estimated accuracy.
  /// For very poor accuracy (> 5000m) the measurement is skipped and
  /// prediction-only is returned.
  ({double lat, double lng, double accuracy}) update({
    required double lat,
    required double lng,
    required double accuracy,
    required DateTime timestamp,
  }) {
    // Sanitize accuracy
    final effectiveAccuracy = accuracy < 0 ? 500.0 : accuracy;

    // Track latest measurement accuracy for adaptive Q
    _lastMeasurementAccuracy = effectiveAccuracy;
    _updateQ();

    // --- First measurement: initialize state directly ---
    if (!_initialized) {
      _refLat = lat;
      _refLng = lng;

      _x[0] = 0; // x
      _x[1] = 0; // y
      _x[2] = 0; // vx
      _x[3] = 0; // vy

      // Large initial covariance
      final r = effectiveAccuracy * effectiveAccuracy;
      _setIdentity(_P, 4);
      _P[0] = r;      // var(x)
      _P[5] = r;      // var(y)
      _P[10] = 100;   // var(vx) — unknown velocity
      _P[15] = 100;   // var(vy)

      _lastTimestamp = timestamp;
      _initialized = true;

      return (lat: lat, lng: lng, accuracy: effectiveAccuracy);
    }

    // --- Time delta ---
    final dt = timestamp.difference(_lastTimestamp!).inMilliseconds / 1000.0;

    // Large time gap (>60s) — reset filter, too much uncertainty
    if (dt > 60.0 || dt < 0) {
      reset();
      return update(
        lat: lat,
        lng: lng,
        accuracy: accuracy,
        timestamp: timestamp,
      );
    }

    // Zero or near-zero dt — skip prediction, just do measurement update
    final doPrediction = dt > 0.01;

    // --- Convert measurement to local meters ---
    final zx = (lng - _refLng!) * cos(_refLat! * pi / 180) * 111320;
    final zy = (lat - _refLat!) * 110540;

    // =================== PREDICTION ===================
    if (doPrediction) {
      // Predicted state: x_pred = F * x
      final px = _x[0] + _x[2] * dt;
      final py = _x[1] + _x[3] * dt;
      final pvx = _x[2];
      final pvy = _x[3];

      _x[0] = px;
      _x[1] = py;
      _x[2] = pvx;
      _x[3] = pvy;

      // P_pred = F * P * Fᵀ + Q
      _predictCovariance(dt);
    }

    _lastTimestamp = timestamp;

    // Very poor accuracy — skip measurement, return prediction only
    if (effectiveAccuracy > 5000) {
      return _stateToLatLng(effectiveAccuracy);
    }

    // =================== MEASUREMENT UPDATE ===================
    final r = effectiveAccuracy * effectiveAccuracy;

    // Innovation: y = z - H * x  (H extracts position only)
    final yx = zx - _x[0];
    final yy = zy - _x[1];

    // S = H * P * Hᵀ + R  (2×2)
    final s00 = _P[0] + r;
    final s01 = _P[1];
    final s10 = _P[4];
    final s11 = _P[5] + r;

    // S⁻¹ (2×2 inverse)
    final det = s00 * s11 - s01 * s10;
    if (det.abs() < 1e-10) {
      // Singular — skip update
      return _stateToLatLng(effectiveAccuracy);
    }
    final invDet = 1.0 / det;
    final si00 = s11 * invDet;
    final si01 = -s01 * invDet;
    final si10 = -s10 * invDet;
    final si11 = s00 * invDet;

    // K = P * Hᵀ * S⁻¹  (4×2)
    // P * Hᵀ is columns 0,1 of P (since H = [I₂ 0₂])
    final k00 = _P[0] * si00 + _P[1] * si10;
    final k01 = _P[0] * si01 + _P[1] * si11;
    final k10 = _P[4] * si00 + _P[5] * si10;
    final k11 = _P[4] * si01 + _P[5] * si11;
    final k20 = _P[8] * si00 + _P[9] * si10;
    final k21 = _P[8] * si01 + _P[9] * si11;
    final k30 = _P[12] * si00 + _P[13] * si10;
    final k31 = _P[12] * si01 + _P[13] * si11;

    // State update: x = x + K * y
    _x[0] += k00 * yx + k01 * yy;
    _x[1] += k10 * yx + k11 * yy;
    _x[2] += k20 * yx + k21 * yy;
    _x[3] += k30 * yx + k31 * yy;

    // Covariance update: P = (I - K*H) * P
    // Using Joseph form for numerical stability:
    // P = (I - KH) * P * (I - KH)ᵀ + K * R * Kᵀ
    // For simplicity, using standard form which is fine for this scale:
    _updateCovariance(k00, k01, k10, k11, k20, k21, k30, k31);

    // Estimated accuracy from covariance
    final estAccuracy = sqrt((_P[0] + _P[5]) / 2);

    return _stateToLatLng(estAccuracy);
  }

  /// Reset filter state
  void reset() {
    _refLat = null;
    _refLng = null;
    _x[0] = 0;
    _x[1] = 0;
    _x[2] = 0;
    _x[3] = 0;
    for (int i = 0; i < 16; i++) {
      _P[i] = 0;
    }
    _lastTimestamp = null;
    _initialized = false;
    _isStationary = false;
    _lastMeasurementAccuracy = 10.0;
    _q = _qBase;
  }

  /// Force filter state to a specific position (e.g. manual "dikira").
  /// Sets reference point, zero velocity, moderate covariance (30m accuracy).
  void forcePosition(double lat, double lng) {
    _refLat = lat;
    _refLng = lng;
    _x[0] = 0; _x[1] = 0; _x[2] = 0; _x[3] = 0;
    const manualAccuracy = 30.0;
    final r = manualAccuracy * manualAccuracy;
    _setIdentity(_P, 4);
    _P[0] = r; _P[5] = r; _P[10] = 4.0; _P[15] = 4.0;
    _lastTimestamp = DateTime.now();
    _initialized = true;
    _isStationary = true;
    _lastMeasurementAccuracy = manualAccuracy;
    _updateQ();
  }

  /// Set motion state — adjusts process noise for ZUPT (Zero Velocity Update).
  /// Stationary: dramatically reduces noise so the filter resists GPS jitter.
  /// Moving: adaptive noise based on GPS accuracy.
  void setMotionState({required bool isStationary}) {
    _isStationary = isStationary;
    if (isStationary) {
      // Zero velocity — prevents accumulated jitter velocity from drifting prediction
      _x[2] = 0;
      _x[3] = 0;
    }
    _updateQ();
  }

  /// Recalculate Q based on motion state and GPS accuracy.
  /// Stationary → fixed low Q (ZUPT). Moving → scales with accuracy.
  void _updateQ() {
    if (_isStationary) {
      _q = _qStationary;
      return;
    }
    final scale = (_referenceAccuracy / _lastMeasurementAccuracy)
        .clamp(_qMinScale, _qMaxScale);
    _q = _qBase * scale;
  }

  // =================== PRIVATE HELPERS ===================

  /// Convert current state back to lat/lng
  ({double lat, double lng, double accuracy}) _stateToLatLng(double accuracy) {
    final lat = _refLat! + _x[1] / 110540;
    final lng = _refLng! + _x[0] / (cos(_refLat! * pi / 180) * 111320);
    return (lat: lat, lng: lng, accuracy: accuracy);
  }

  /// P_pred = F * P * Fᵀ + Q
  void _predictCovariance(double dt) {
    final dt2 = dt * dt;
    final dt3 = dt2 * dt;

    // F * P (multiply F on left — F only differs from I by dt in [0,2] and [1,3])
    // Row 0 of F*P = row0(P) + dt * row2(P)
    // Row 1 of F*P = row1(P) + dt * row3(P)
    // Row 2 of F*P = row2(P)
    // Row 3 of F*P = row3(P)
    final List<double> fp = List.filled(16, 0);
    for (int j = 0; j < 4; j++) {
      fp[0 * 4 + j] = _P[0 * 4 + j] + dt * _P[2 * 4 + j];
      fp[1 * 4 + j] = _P[1 * 4 + j] + dt * _P[3 * 4 + j];
      fp[2 * 4 + j] = _P[2 * 4 + j];
      fp[3 * 4 + j] = _P[3 * 4 + j];
    }

    // (F*P) * Fᵀ — Fᵀ only differs from I by dt in [2,0] and [3,1]
    // Col 0 of result = col0(FP) + dt * col2(FP) ... wait, transpose:
    // Column j of Fᵀ: col j of Fᵀ = row j of F
    // So (FP)*Fᵀ: element [i,j] = sum_k FP[i,k] * F[j,k]
    // F[0,k] = [1, 0, dt, 0]
    // F[1,k] = [0, 1, 0, dt]
    // F[2,k] = [0, 0, 1, 0]
    // F[3,k] = [0, 0, 0, 1]
    for (int i = 0; i < 4; i++) {
      final a = fp[i * 4 + 0];
      final b = fp[i * 4 + 1];
      final c = fp[i * 4 + 2];
      final d = fp[i * 4 + 3];
      _P[i * 4 + 0] = a + dt * c;
      _P[i * 4 + 1] = b + dt * d;
      _P[i * 4 + 2] = c;
      _P[i * 4 + 3] = d;
    }

    // Add Q (process noise)
    _P[0] += _q * dt3 / 3;   // var(x)
    _P[5] += _q * dt3 / 3;   // var(y)
    _P[10] += _q * dt;        // var(vx)
    _P[15] += _q * dt;        // var(vy)

    // Cross terms
    _P[2] += _q * dt2 / 2;   // cov(x, vx)
    _P[8] += _q * dt2 / 2;   // cov(vx, x)
    _P[7] += _q * dt2 / 2;   // cov(y, vy)
    _P[13] += _q * dt2 / 2;  // cov(vy, y)
  }

  /// P = (I - K*H) * P
  /// K is 4×2, H is 2×4 = [I₂ | 0₂]
  /// So K*H is 4×4 where (KH)[i,j] = K[i,0]*H[0,j] + K[i,1]*H[1,j]
  /// H[0,j] = [1,0,0,0], H[1,j] = [0,1,0,0]
  /// So (KH)[i,j] = K[i,0] if j==0, K[i,1] if j==1, 0 otherwise
  void _updateCovariance(
    double k00, double k01,
    double k10, double k11,
    double k20, double k21,
    double k30, double k31,
  ) {
    // (I - KH) matrix:
    // [1-k00, -k01,  0, 0]
    // [-k10,  1-k11, 0, 0]
    // [-k20,  -k21,  1, 0]
    // [-k30,  -k31,  0, 1]
    final List<double> ikh = [
      1 - k00, -k01, 0, 0,
      -k10, 1 - k11, 0, 0,
      -k20, -k21, 1, 0,
      -k30, -k31, 0, 1,
    ];

    // result = ikh * P
    final List<double> result = List.filled(16, 0);
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        double sum = 0;
        for (int k = 0; k < 4; k++) {
          sum += ikh[i * 4 + k] * _P[k * 4 + j];
        }
        result[i * 4 + j] = sum;
      }
    }

    for (int i = 0; i < 16; i++) {
      _P[i] = result[i];
    }
  }

  /// Set matrix to identity * scale
  void _setIdentity(List<double> m, int n) {
    for (int i = 0; i < n * n; i++) {
      m[i] = 0;
    }
    for (int i = 0; i < n; i++) {
      m[i * n + i] = 1;
    }
  }
}
