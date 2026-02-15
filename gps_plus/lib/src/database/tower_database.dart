import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/cell_tower_info.dart';
import '../models/tower_location.dart';

/// SQLite database for storing known cell tower locations.
class TowerDatabase {
  Database? _db;

  /// Whether the database has been initialized.
  bool get isInitialized => _db != null;

  /// Opens (or creates) the tower database.
  Future<void> initialize() async {
    if (_db != null) return;

    final dir = await getApplicationSupportDirectory();
    final path = '${dir.path}/gps_plus_towers.db';

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE towers (
            mcc INTEGER NOT NULL,
            mnc INTEGER NOT NULL,
            lac INTEGER NOT NULL,
            cid INTEGER NOT NULL,
            lat REAL NOT NULL,
            lon REAL NOT NULL,
            range INTEGER NOT NULL DEFAULT 1000,
            type TEXT NOT NULL DEFAULT 'GSM',
            PRIMARY KEY (mcc, mnc, lac, cid)
          )
        ''');
        await db.execute('''
          CREATE INDEX idx_towers_lookup ON towers (mcc, mnc, lac, cid)
        ''');
      },
    );
  }

  /// Looks up a tower's known location by its identity.
  Future<TowerLocation?> lookupTower(CellTowerInfo tower) async {
    _ensureInitialized();

    final results = await _db!.query(
      'towers',
      where: 'mcc = ? AND mnc = ? AND lac = ? AND cid = ?',
      whereArgs: [tower.mcc, tower.mnc, tower.lac, tower.cid],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return TowerLocation.fromMap(results.first);
  }

  /// Looks up multiple towers at once. Returns a map of found towers
  /// keyed by their index in the input list.
  Future<Map<int, TowerLocation>> lookupTowers(
    List<CellTowerInfo> towers,
  ) async {
    _ensureInitialized();
    if (towers.isEmpty) return {};

    // Build a single query with OR conditions
    final whereParts = <String>[];
    final whereArgs = <dynamic>[];
    for (final tower in towers) {
      whereParts.add('(mcc = ? AND mnc = ? AND lac = ? AND cid = ?)');
      whereArgs.addAll([tower.mcc, tower.mnc, tower.lac, tower.cid]);
    }

    final results = await _db!.query(
      'towers',
      where: whereParts.join(' OR '),
      whereArgs: whereArgs,
    );

    // Map results back to input indices
    final resultMap = <int, TowerLocation>{};
    for (final row in results) {
      final location = TowerLocation.fromMap(row);
      // Find the matching input tower index
      for (var i = 0; i < towers.length; i++) {
        if (towers[i].mcc == location.mcc &&
            towers[i].mnc == location.mnc &&
            towers[i].lac == location.lac &&
            towers[i].cid == location.cid) {
          resultMap[i] = location;
          break;
        }
      }
    }
    return resultMap;
  }

  /// Inserts or replaces tower records in bulk.
  Future<int> insertTowers(List<TowerLocation> towers) async {
    _ensureInitialized();

    var count = 0;
    final batch = _db!.batch();
    for (final tower in towers) {
      batch.insert(
        'towers',
        tower.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      count++;

      // Commit in batches of 1000 for efficiency
      if (count % 1000 == 0) {
        await batch.commit(noResult: true);
      }
    }
    await batch.commit(noResult: true);
    return count;
  }

  /// Returns the number of towers stored for a given MCC.
  Future<int> countTowers({int? mcc}) async {
    _ensureInitialized();

    final result = mcc != null
        ? await _db!.rawQuery(
            'SELECT COUNT(*) as cnt FROM towers WHERE mcc = ?', [mcc])
        : await _db!.rawQuery('SELECT COUNT(*) as cnt FROM towers');

    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Deletes all towers for a given MCC.
  Future<int> deleteTowers({required int mcc}) async {
    _ensureInitialized();
    return await _db!.delete('towers', where: 'mcc = ?', whereArgs: [mcc]);
  }

  /// Closes the database.
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  void _ensureInitialized() {
    if (_db == null) {
      throw StateError(
        'TowerDatabase not initialized. Call initialize() first.',
      );
    }
  }
}
