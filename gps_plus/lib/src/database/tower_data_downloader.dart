import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:http/http.dart' as http;

import '../models/tower_location.dart';
import 'tower_database.dart';

/// Downloads cell tower data from OpenCellID and stores it in the local database.
class TowerDataDownloader {
  final TowerDatabase _database;
  final http.Client _httpClient;

  /// OpenCellID API base URL.
  /// Requires an API key from https://opencellid.org
  static const _baseUrl = 'https://opencellid.org/cell/getInArea';

  TowerDataDownloader({
    required TowerDatabase database,
    http.Client? httpClient,
  })  : _database = database,
        _httpClient = httpClient ?? http.Client();

  /// Downloads tower data for a given MCC (country code) using the
  /// OpenCellID bulk download endpoint.
  ///
  /// [apiKey] - Your OpenCellID API key.
  /// [mcc] - Mobile Country Code (e.g., 425 for Israel).
  /// [onProgress] - Optional callback for download progress reporting.
  ///
  /// Returns the number of towers downloaded and stored.
  Future<int> downloadByMcc({
    required String apiKey,
    required int mcc,
    void Function(int downloaded, int total)? onProgress,
  }) async {
    // Use the OpenCellID cell CSV download endpoint
    final url = Uri.parse(
      'https://opencellid.org/ocid/downloads?token=$apiKey'
      '&type=mcc&file=$mcc.csv.gz',
    );

    final response = await _httpClient.get(url);

    if (response.statusCode != 200) {
      throw TowerDownloadException(
        'Failed to download tower data: HTTP ${response.statusCode}',
      );
    }

    // Parse CSV data
    final csvString = utf8.decode(response.bodyBytes);
    final towers = _parseCsv(csvString);

    if (towers.isEmpty) {
      throw TowerDownloadException(
        'No tower data found for MCC $mcc',
      );
    }

    // Store in database
    final count = await _database.insertTowers(towers);
    onProgress?.call(count, count);

    return count;
  }

  /// Downloads towers for a specific geographic area.
  ///
  /// [apiKey] - Your OpenCellID API key.
  /// [latMin], [lonMin], [latMax], [lonMax] - Bounding box.
  ///
  /// Returns the number of towers downloaded and stored.
  Future<int> downloadByArea({
    required String apiKey,
    required double latMin,
    required double lonMin,
    required double latMax,
    required double lonMax,
  }) async {
    final url = Uri.parse(
      '$_baseUrl?key=$apiKey'
      '&BBOX=$latMin,$lonMin,$latMax,$lonMax'
      '&format=csv',
    );

    final response = await _httpClient.get(url);

    if (response.statusCode != 200) {
      throw TowerDownloadException(
        'Failed to download tower data: HTTP ${response.statusCode}',
      );
    }

    final csvString = utf8.decode(response.bodyBytes);
    final towers = _parseCsv(csvString);

    if (towers.isEmpty) return 0;

    return await _database.insertTowers(towers);
  }

  /// Parses OpenCellID CSV format into TowerLocation objects.
  ///
  /// Expected CSV columns:
  /// radio,mcc,net,area,cell,unit,lon,lat,range,samples,changeable,created,updated,averageSignal
  List<TowerLocation> _parseCsv(String csvString) {
    final converter = const CsvToListConverter();
    final rows = converter.convert(csvString);

    if (rows.isEmpty) return [];

    // Skip header row
    final towers = <TowerLocation>[];
    for (var i = 1; i < rows.length; i++) {
      try {
        final row = rows[i];
        if (row.length < 9) continue;

        final radioType = row[0].toString().toUpperCase();
        final mcc = _parseInt(row[1]);
        final mnc = _parseInt(row[2]);
        final lac = _parseInt(row[3]);
        final cid = _parseInt(row[4]);
        final lon = _parseDouble(row[6]);
        final lat = _parseDouble(row[7]);
        final range = _parseInt(row[8]);

        if (mcc == null ||
            mnc == null ||
            lac == null ||
            cid == null ||
            lat == null ||
            lon == null) {
          continue;
        }

        towers.add(TowerLocation(
          mcc: mcc,
          mnc: mnc,
          lac: lac,
          cid: cid,
          lat: lat,
          lon: lon,
          range: range ?? 1000,
          type: radioType,
        ));
      } catch (_) {
        // Skip malformed rows
        continue;
      }
    }

    return towers;
  }

  int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  double? _parseDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// Disposes of the HTTP client.
  void dispose() {
    _httpClient.close();
  }
}

/// Exception thrown when tower data download fails.
class TowerDownloadException implements Exception {
  final String message;
  const TowerDownloadException(this.message);

  @override
  String toString() => 'TowerDownloadException: $message';
}
