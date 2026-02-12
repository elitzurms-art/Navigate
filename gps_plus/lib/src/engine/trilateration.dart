import 'dart:math';

import 'package:latlong2/latlong.dart';

/// Trilateration algorithm for determining position from 3+ tower positions
/// and estimated distances.
///
/// Converts geodetic coordinates to a local Cartesian coordinate system,
/// solves the system of equations, then converts back.
class Trilateration {
  const Trilateration();

  /// Calculates position from tower locations and distances.
  ///
  /// [towers] - List of known tower positions (lat/lon).
  /// [distances] - Corresponding estimated distances in meters.
  ///
  /// Returns the estimated position, or null if calculation fails.
  /// Requires at least 3 towers.
  TrilaterationResult? calculate({
    required List<LatLng> towers,
    required List<double> distances,
  }) {
    if (towers.length < 3 || towers.length != distances.length) {
      return null;
    }

    // Use the first tower as the local coordinate origin
    final origin = towers[0];
    final originLatRad = origin.latitudeInRad;
    final originLonRad = origin.longitudeInRad;

    // Convert all towers to local Cartesian (meters) relative to origin
    final points = <_Point>[];
    for (final tower in towers) {
      final x = _lonToMeters(tower.longitudeInRad - originLonRad, originLatRad);
      final y = _latToMeters(tower.latitudeInRad - originLatRad);
      points.add(_Point(x, y));
    }

    // Build the system of linear equations using the standard approach:
    // For each pair of circles (i, 0), subtract circle 0's equation:
    //   2*(xi - x0)*x + 2*(yi - y0)*y = di^2 - d0^2 - xi^2 + x0^2 - yi^2 + y0^2
    //
    // Since we use tower[0] as origin, x0=0, y0=0:
    //   2*xi*x + 2*yi*y = d0^2 - di^2 + xi^2 + yi^2

    final n = towers.length;
    final rows = n - 1;

    // Build A matrix and b vector
    final a = List.generate(rows, (_) => List.filled(2, 0.0));
    final b = List.filled(rows, 0.0);

    for (var i = 0; i < rows; i++) {
      final pi = points[i + 1];
      a[i][0] = 2.0 * pi.x;
      a[i][1] = 2.0 * pi.y;
      b[i] = distances[0] * distances[0] -
          distances[i + 1] * distances[i + 1] +
          pi.x * pi.x +
          pi.y * pi.y;
    }

    // Solve via least squares: x = (A^T * A)^-1 * A^T * b
    final result = _leastSquaresSolve(a, b);
    if (result == null) return null;

    final solX = result[0];
    final solY = result[1];

    // Convert back to lat/lon
    final lat = origin.latitude + _metersToLatDeg(solY);
    final lon = origin.longitude + _metersToLonDeg(solX, originLatRad);

    // Calculate residuals for accuracy estimation
    var residualSum = 0.0;
    for (var i = 0; i < n; i++) {
      final dx = solX - points[i].x;
      final dy = solY - points[i].y;
      final actualDist = sqrt(dx * dx + dy * dy);
      final residual = (actualDist - distances[i]).abs();
      residualSum += residual * residual;
    }
    final rmse = sqrt(residualSum / n);

    return TrilaterationResult(
      position: LatLng(lat, lon),
      accuracyMeters: rmse,
    );
  }

  /// Solves Ax = b via least squares using normal equations (A^T*A)x = A^T*b.
  /// Returns [x, y] or null if the system is singular.
  List<double>? _leastSquaresSolve(
    List<List<double>> a,
    List<double> b,
  ) {
    final rows = a.length;

    // Compute A^T * A (2x2)
    double ata00 = 0, ata01 = 0, ata11 = 0;
    for (var i = 0; i < rows; i++) {
      ata00 += a[i][0] * a[i][0];
      ata01 += a[i][0] * a[i][1];
      ata11 += a[i][1] * a[i][1];
    }

    // Compute A^T * b (2x1)
    double atb0 = 0, atb1 = 0;
    for (var i = 0; i < rows; i++) {
      atb0 += a[i][0] * b[i];
      atb1 += a[i][1] * b[i];
    }

    // Solve 2x2 system using Cramer's rule
    final det = ata00 * ata11 - ata01 * ata01;
    if (det.abs() < 1e-10) return null; // Singular (collinear towers)

    final x = (ata11 * atb0 - ata01 * atb1) / det;
    final y = (ata00 * atb1 - ata01 * atb0) / det;

    return [x, y];
  }

  // Conversion helpers (WGS84 approximations)

  static const double _earthRadius = 6371000.0; // meters

  double _lonToMeters(double dLonRad, double latRad) {
    return dLonRad * _earthRadius * cos(latRad);
  }

  double _latToMeters(double dLatRad) {
    return dLatRad * _earthRadius;
  }

  double _metersToLatDeg(double meters) {
    return meters / _earthRadius * (180.0 / pi);
  }

  double _metersToLonDeg(double meters, double latRad) {
    return meters / (_earthRadius * cos(latRad)) * (180.0 / pi);
  }
}

class _Point {
  final double x;
  final double y;
  const _Point(this.x, this.y);
}

/// Result from trilateration calculation.
class TrilaterationResult {
  final LatLng position;
  final double accuracyMeters;

  const TrilaterationResult({
    required this.position,
    required this.accuracyMeters,
  });
}
