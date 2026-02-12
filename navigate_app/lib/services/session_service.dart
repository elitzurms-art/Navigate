import 'package:shared_preferences/shared_preferences.dart';
import '../domain/entities/hat_type.dart';
import '../data/repositories/navigation_tree_repository.dart';
import '../data/repositories/unit_repository.dart';

/// שירות ניהול session — סריקת כובעים, שמירה וטעינה
class SessionService {
  static final SessionService _instance = SessionService._internal();
  factory SessionService() => _instance;
  SessionService._internal();

  final NavigationTreeRepository _treeRepository = NavigationTreeRepository();
  final UnitRepository _unitRepository = UnitRepository();

  // מפתחות SharedPreferences
  static const _keyHatType = 'session_hat_type';
  static const _keySubFrameworkId = 'session_sub_framework_id';
  static const _keySubFrameworkName = 'session_sub_framework_name';
  static const _keyTreeId = 'session_tree_id';
  static const _keyTreeName = 'session_tree_name';
  static const _keyUnitId = 'session_unit_id';
  static const _keyUnitName = 'session_unit_name';

  /// סריקת כל הכובעים של המשתמש — סריקת היררכיית יחידות ועצי ניווט
  Future<List<UnitHats>> scanUserHats(String uid) async {
    final trees = await _treeRepository.getAll();
    final allUnits = await _unitRepository.getAll();
    final hatsByUnit = <String, List<HatInfo>>{};
    final unitNames = <String, String>{};

    // מיפוי שמות יחידות
    for (final unit in allUnits) {
      unitNames[unit.id] = unit.name;
    }

    // סריקת עצי ניווט — בדיקת תתי-מסגרות
    for (final tree in trees) {
      final treeUnitId = tree.unitId;
      if (treeUnitId == null || treeUnitId.isEmpty) continue;

      final unitName = unitNames[treeUnitId];
      if (unitName == null) {
        // יחידה נמחקה — דילוג
        print('DEBUG scanUserHats: skipping tree ${tree.id} — unit $treeUnitId deleted');
        continue;
      }

      // בדיקת תתי-מסגרות לפי שם
      for (final subFramework in tree.subFrameworks) {
        if (!subFramework.userIds.contains(uid)) continue;

        final hatType = _resolveHatType(subFramework.name);
        hatsByUnit.putIfAbsent(treeUnitId, () => []);
        hatsByUnit[treeUnitId]!.add(HatInfo(
          type: hatType,
          subFrameworkId: subFramework.id,
          subFrameworkName: subFramework.name,
          treeId: tree.id,
          treeName: tree.name,
          unitId: treeUnitId,
          unitName: unitName,
        ));
      }
    }

    // בדיקת יחידות שהמשתמש מנהל אותן — כובע admin
    for (final unit in allUnits) {
      if (!unit.managerIds.contains(uid)) continue;
      hatsByUnit.putIfAbsent(unit.id, () => []);
      // הוספת כובע admin רק אם אין כבר
      final hasAdmin = hatsByUnit[unit.id]!.any((h) => h.type == HatType.admin);
      if (!hasAdmin) {
        // חיפוש עץ ליחידה זו
        final unitTree = trees.where((t) => t.unitId == unit.id).firstOrNull;
        hatsByUnit[unit.id]!.add(HatInfo(
          type: HatType.admin,
          treeId: unitTree?.id ?? '',
          treeName: unitTree?.name ?? '',
          unitId: unit.id,
          unitName: unit.name,
        ));
      }
      unitNames[unit.id] = unit.name;
    }

    // המרה ל-List<UnitHats>
    return hatsByUnit.entries.map((entry) {
      return UnitHats(
        unitId: entry.key,
        unitName: unitNames[entry.key] ?? '',
        hats: entry.value,
      );
    }).toList();
  }

  /// פענוח סוג כובע לפי שם תת-מסגרת
  HatType _resolveHatType(String subFrameworkName) {
    final name = subFrameworkName.trim();
    if (name == 'מפקדים' || name.contains('מפקד')) {
      return HatType.commander;
    }
    if (name == 'מנהלת' || name.contains('מנהל')) {
      return HatType.management;
    }
    if (name == 'מבקרים' || name.contains('מבקר')) {
      return HatType.observer;
    }
    // ברירת מחדל — מנווט (כולל מסגרות היררכיות וחיילים)
    return HatType.navigator;
  }

  /// קריאת session שמור מ-SharedPreferences
  Future<HatInfo?> getSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final hatTypeName = prefs.getString(_keyHatType);
    if (hatTypeName == null) return null;

    final treeId = prefs.getString(_keyTreeId);
    final treeName = prefs.getString(_keyTreeName);
    final unitId = prefs.getString(_keyUnitId);
    final unitName = prefs.getString(_keyUnitName);

    if (unitId == null) return null;

    HatType type;
    try {
      type = HatType.values.byName(hatTypeName);
    } catch (_) {
      return null;
    }

    return HatInfo(
      type: type,
      subFrameworkId: prefs.getString(_keySubFrameworkId),
      subFrameworkName: prefs.getString(_keySubFrameworkName),
      treeId: treeId ?? '',
      treeName: treeName ?? '',
      unitId: unitId,
      unitName: unitName ?? '',
    );
  }

  /// שמירת session ב-SharedPreferences
  Future<void> saveSession(HatInfo hat) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyHatType, hat.type.name);
    await prefs.setString(_keyTreeId, hat.treeId);
    await prefs.setString(_keyTreeName, hat.treeName);
    await prefs.setString(_keyUnitId, hat.unitId);
    await prefs.setString(_keyUnitName, hat.unitName);

    if (hat.subFrameworkId != null) {
      await prefs.setString(_keySubFrameworkId, hat.subFrameworkId!);
    } else {
      await prefs.remove(_keySubFrameworkId);
    }
    if (hat.subFrameworkName != null) {
      await prefs.setString(_keySubFrameworkName, hat.subFrameworkName!);
    } else {
      await prefs.remove(_keySubFrameworkName);
    }

    // ניקוי מפתחות ישנים (framework)
    await prefs.remove('session_framework_id');
    await prefs.remove('session_framework_name');
  }

  /// ניקוי כל מפתחות session
  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyHatType);
    await prefs.remove(_keySubFrameworkId);
    await prefs.remove(_keySubFrameworkName);
    await prefs.remove(_keyTreeId);
    await prefs.remove(_keyTreeName);
    await prefs.remove(_keyUnitId);
    await prefs.remove(_keyUnitName);
    // ניקוי מפתחות ישנים
    await prefs.remove('session_framework_id');
    await prefs.remove('session_framework_name');
  }

}
