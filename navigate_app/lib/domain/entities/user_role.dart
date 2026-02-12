/// תפקידי משתמש במערכת
enum UserRole {
  /// מפתח - גישה מלאה לכל המערכת
  developer('developer', 'מפתח'),

  /// מנהל מערכת יחידתי - ניהול יחידה
  unitAdmin('unit_admin', 'מנהל מערכת יחידתי'),

  /// מפקד - יצירת וניהול ניווטים
  commander('commander', 'מפקד'),

  /// מנווט - צפייה והשתתפות בניווטים
  navigator('navigator', 'מנווט'),

  /// אורח - לבדיקות (נמחק בפרודקשן)
  guestDeveloper('guest_developer', 'אורח - מפתח'),
  guestCommander('guest_commander', 'אורח - מפקד'),
  guestNavigator('guest_navigator', 'אורח - מנווט');

  final String code;
  final String displayName;

  const UserRole(this.code, this.displayName);

  /// בדיקות הרשאות
  bool get isDeveloper => this == UserRole.developer || this == UserRole.guestDeveloper;
  bool get isUnitAdmin => this == UserRole.unitAdmin;
  bool get isCommander => this == UserRole.commander || this == UserRole.guestCommander;
  bool get isNavigator => this == UserRole.navigator || this == UserRole.guestNavigator;
  bool get isGuest => code.startsWith('guest_');

  /// הרשאות ברמה גבוהה
  bool get canCreateUnits => isDeveloper;
  bool get canManageUnit => isDeveloper || isUnitAdmin;
  bool get canCreateNavigations => isDeveloper || isUnitAdmin || isCommander;
  bool get canViewNavigations => true; // כולם יכולים לצפות (לפי הרשאות ספציפיות)

  static UserRole fromCode(String code) {
    return UserRole.values.firstWhere(
      (role) => role.code == code,
      orElse: () => UserRole.navigator,
    );
  }
}
