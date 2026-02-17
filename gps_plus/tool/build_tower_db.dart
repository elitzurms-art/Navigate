/// One-time script to build the bundled tower database from OpenCellID.
///
/// Usage:
///   dart run tool/build_tower_db.dart <API_KEY>
///
/// Downloads MCC 425 (Israel) cell tower data from OpenCellID and creates
/// the SQLite database at assets/gps_plus_towers.db.
///
/// Requires `sqlite3` package to be available.
import 'dart:io';
import 'dart:convert';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run tool/build_tower_db.dart <OPENCELLID_API_KEY>');
    print('');
    print('Downloads MCC 425 (Israel) tower data and creates assets/gps_plus_towers.db');
    exit(1);
  }

  final apiKey = args[0];
  const mcc = 425;
  final dbPath = '${Directory.current.path}/assets/gps_plus_towers.db';
  final csvPath = '${Directory.current.path}/tool/towers_$mcc.csv.gz';

  // Step 1: Download the CSV from OpenCellID
  print('Downloading MCC $mcc tower data from OpenCellID...');
  final url = 'https://opencellid.org/ocid/downloads'
      '?token=$apiKey&type=mcc&file=$mcc.csv.gz';

  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();

    if (response.statusCode != 200) {
      print('Error: HTTP ${response.statusCode}');
      exit(1);
    }

    final file = File(csvPath);
    final sink = file.openWrite();
    await response.pipe(sink);
    print('Downloaded to $csvPath');

    // Step 2: Decompress
    print('Decompressing...');
    final gzBytes = await file.readAsBytes();
    final csvBytes = gzip.decode(gzBytes);
    final csvContent = utf8.decode(csvBytes);
    final lines = csvContent.split('\n');
    print('Got ${lines.length} lines');

    // Step 3: Delete existing DB if present
    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      await dbFile.delete();
    }

    // Step 4: Create database using sqlite3 CLI
    print('Creating SQLite database at $dbPath...');

    // Write SQL commands to a temp file
    final sqlFile = File('${Directory.current.path}/tool/import.sql');
    final sqlSink = sqlFile.openWrite();

    sqlSink.writeln('CREATE TABLE towers (');
    sqlSink.writeln('  mcc INTEGER NOT NULL,');
    sqlSink.writeln('  mnc INTEGER NOT NULL,');
    sqlSink.writeln('  lac INTEGER NOT NULL,');
    sqlSink.writeln('  cid INTEGER NOT NULL,');
    sqlSink.writeln('  lat REAL NOT NULL,');
    sqlSink.writeln('  lon REAL NOT NULL,');
    sqlSink.writeln('  range INTEGER NOT NULL DEFAULT 1000,');
    sqlSink.writeln('  type TEXT NOT NULL DEFAULT \'GSM\',');
    sqlSink.writeln('  PRIMARY KEY (mcc, mnc, lac, cid)');
    sqlSink.writeln(');');
    sqlSink.writeln('CREATE INDEX idx_towers_lookup ON towers (mcc, mnc, lac, cid);');
    sqlSink.writeln('BEGIN TRANSACTION;');

    // Parse CSV: radio,mcc,net,area,cell,unit,lon,lat,range,samples,changeable,created,updated,averageSignal
    int count = 0;
    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final parts = line.split(',');
      if (parts.length < 9) continue;

      final radio = parts[0];
      final mccVal = int.tryParse(parts[1]) ?? 0;
      final mnc = int.tryParse(parts[2]) ?? 0;
      final lac = int.tryParse(parts[3]) ?? 0;
      final cid = int.tryParse(parts[4]) ?? 0;
      final lon = double.tryParse(parts[6]) ?? 0.0;
      final lat = double.tryParse(parts[7]) ?? 0.0;
      final range = int.tryParse(parts[8]) ?? 1000;

      if (lat == 0.0 && lon == 0.0) continue;
      if (mccVal != mcc) continue;

      sqlSink.writeln(
        "INSERT OR REPLACE INTO towers (mcc, mnc, lac, cid, lat, lon, range, type) "
        "VALUES ($mccVal, $mnc, $lac, $cid, $lat, $lon, $range, '$radio');",
      );
      count++;

      if (count % 10000 == 0) {
        sqlSink.writeln('COMMIT;');
        sqlSink.writeln('BEGIN TRANSACTION;');
      }
    }

    sqlSink.writeln('COMMIT;');
    await sqlSink.close();

    // Execute SQL using sqlite3 CLI
    final result = await Process.run('sqlite3', [dbPath, '.read ${sqlFile.path}']);
    if (result.exitCode != 0) {
      print('sqlite3 error: ${result.stderr}');
      print('');
      print('Make sure sqlite3 CLI is installed and in PATH.');
      print('Alternatively, you can manually import the SQL file.');
      exit(1);
    }

    print('Successfully created $dbPath with $count towers');

    // Cleanup temp files
    await sqlFile.delete();
    await file.delete();
  } finally {
    client.close();
  }
}
