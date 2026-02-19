import 'package:shared_preferences/shared_preferences.dart';
import '../domain/entities/hat_type.dart';
import '../data/repositories/navigation_tree_repository.dart';
import '../data/repositories/unit_repository.dart';
import '../data/repositories/user_repository.dart';

/// שירות ניהול session — סריקת כובעים, שמירה וטעינה
class SessionService {
  static final SessionService _instance = SessionService._internal();
  factory SessionService() => _instance;
  SessionService._internal();

  final NavigationTreeRepository _treeRepository = NavigationTreeRepository();
  final UnitRepository _unitRepository = UnitRepository();
  final UserRepository _userRepository = UserRepository();

  // מפתחות SharedPreferences
  static const _keyHatType = 'session_hat_type';
  static const _keySubFrameworkId = 'session_sub_framework_id';
  static const _keySubFrameworkName = 'session_sub_framework_name';
  static const _keyTreeId = 'session_tree_id';
  static const _keyTreeName = 'session_tree_name';
  static const _keyUnitId = 'session_unit_id';
  static const _keyUnitName = 'session_unit_name';

  /// קבלת כובע יחיד של המשתמש — לפי תפקיד (role) ויחידה
  ///
  /// מחפש את תת-המסגרת האמיתית של המשתמש בעץ הניווט (לא ID סינתטי),
  /// כי ב-navigations_list_screen הסינון משווה session.subFrameworkId
  /// מול navigation.selectedSubFrameworkIds שמכילים IDs אמיתיים מהעץ.
  Future<HatInfo?> getUserHat(String uid) async {
    final user = await _userRepository.getUser(uid);
    if (user == null || !user.isApproved || user.unitId == null) return null;

    final trees = await _treeRepository.getAll();
    final allUnits = await _unitRepository.getAll();
    final unitNames = <String, String>{};

    for (final unit in allUnits) {
      unitNames[unit.id] = unit.name;
    }

    final userUnitId = user.unitId!;
    final unitName = unitNames[userUnitId];
    if (unitName == null) return null;

    // חיפוש עץ ליחידה
    final unitTree = trees.where((t) => t.unitId == userUnitId).firstOrNull;

    // חיפוש תת-מסגרת אמיתית שהמשתמש שייך אליה
    String? realSubFrameworkId;
    String realSubFrameworkName = '';
    HatType hatType = HatType.navigator;

    if (unitTree != null) {
      for (final sf in unitTree.subFrameworks) {
        if (sf.userIds.contains(uid)) {
          realSubFrameworkId = sf.id;
          realSubFrameworkName = sf.name;
          hatType = _resolveHatType(sf.name);
          break;
        }
      }
    }

    // בדיקה אם המשתמש מנהל את היחידה שלו — כובע admin
    final isManagerOfOwnUnit = allUnits.any((u) =>
        u.id == userUnitId && u.managerIds.contains(uid));

    // קביעת כובע לפי role ותת-מסגרת
    final role = user.role;
    if (isManagerOfOwnUnit) {
      hatType = HatType.admin;
    } else if (role == 'commander' || role == 'unit_admin' || role == 'admin' || role == 'developer') {
      if (hatType == HatType.navigator) hatType = HatType.commander;
    }

    // אם לא נמצאה תת-מסגרת — מנהל/מפקד רואים הכל (ללא סינון תת-מסגרת)
    // לכן subFrameworkId ריק → הסינון ב-navigations_list_screen מדלג
    return HatInfo(
      type: hatType,
      subFrameworkId: realSubFrameworkId ?? '',
      subFrameworkName: realSubFrameworkName,
      treeId: unitTree?.id ?? '',
      treeName: unitTree?.name ?? '',
      unitId: userUnitId,
      unitName: unitName,
    );
  }

  /// פענוח סוג כובע לפי שם תת-מסגרת
  HatType _resolveHatType(String subFrameworkName) {
    final name = subFrameworkName.trim();
    if (name == 'מפקדים' || name.contains('מפקד') || name.contains('מנהלת')) {
      return HatType.commander;
    }
    if (name == 'מבקרים' || name.contains('מבקר')) {
      return HatType.commander;
    }
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
